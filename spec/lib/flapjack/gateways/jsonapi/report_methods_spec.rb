require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::ReportMethods', :sinatra => true, :logger => true do

  include_context "jsonapi"

  let(:check)    { double(Flapjack::Data::Check, :id => '666') }

  let(:check_presenter) { double(Flapjack::Gateways::JSONAPI::CheckPresenter) }

  let(:report_data) { {'report' => 'data'}}

  def result_data(report_type)
    {
      report_type => [
        report_data.merge(
        :links => {
          :check  => [check.id]
        })],
      :linked => {
        :checks => [{'check' => 'json'}]
      }
     }
  end

  def expect_checks(path, report_type, action_pres, opts = {})
    if opts[:start] && opts[:finish]
      expect(check_presenter).to receive(action_pres).
        with(opts[:start].to_i, opts[:finish].to_i).
        and_return(report_data)
    else
      expect(check_presenter).to receive(action_pres).and_return(report_data)
    end

    expect(Flapjack::Gateways::JSONAPI::CheckPresenter).to receive(:new).
      with(check).and_return(check_presenter)

    if opts[:all]
      expect(Flapjack::Data::Check).to receive(:all).and_return([check])
    elsif opts[:some]
      expect(Flapjack::Data::Check).to receive(:find_by_ids!).
        with(check.id).and_return([check])
    end

    expect(check).to receive(:as_json).and_return({'check' => 'json'})

    result = result_data("#{report_type}_reports")

    par = opts[:start] && opts[:finish] ?
      {:start_time => opts[:start].iso8601, :end_time => opts[:finish].iso8601} : {}

    get path, par
    expect(last_response).to be_ok
    expect(last_response.body).to eq(Flapjack.dump_json(result))
  end

  [:status, :scheduled_maintenance, :unscheduled_maintenance, :outage,
   :downtime].each do |report_type|

    action_pres = case report_type
    when :status, :downtime
      report_type
    else
      "#{report_type}s"
    end

    it "returns a #{report_type} report for all checks" do
      expect_checks("/#{report_type}_report/checks", report_type, action_pres, :all => true)
    end

    it "returns a #{report_type} report for some checks" do
      expect_checks("/#{report_type}_report/checks/#{check.id}", report_type, action_pres, :some => true)
    end

    it "doesn't return a #{report_type} report for a check that's not found" do
      expect(Flapjack::Data::Check).to receive(:find_by_ids!).
        with(check.id).
        and_raise(Sandstorm::Records::Errors::RecordsNotFound.new(Flapjack::Data::Check, [check.id]))

      get "/#{report_type}_report/checks/#{check.id}"
      expect(last_response).to be_not_found
    end

    unless :status.eql?(report_type)

      let(:start)  { Time.parse('1 Jan 2012') }
      let(:finish) { Time.parse('6 Jan 2012') }

      it "returns a #{report_type} report for all checks within a time window" do
        expect_checks("/#{report_type}_report/checks", report_type, action_pres, :all => true,
          :start => start, :finish => finish)
      end

      it "returns a #{report_type} report for some checks within a time window" do
        expect_checks("/#{report_type}_report/checks/#{check.id}", report_type,
          action_pres, :some => true, :start => start, :finish => finish)
      end

    end

  end
end