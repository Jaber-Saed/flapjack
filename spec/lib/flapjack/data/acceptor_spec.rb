require 'spec_helper'
require 'flapjack/data/acceptor'

describe Flapjack::Data::Acceptor, :redis => true do

  let(:weekdays_8_18) {
    wd = IceCube::Schedule.new(Time.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
    wd.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
    wd = wd.to_hash
    wd[:start_time] = wd.delete(:start_date)
    wd[:rrules].first[:rule_type] = wd[:rrules].first[:rule_type].sub(/\AIceCube::(\w+)Rule\z/, '\1')
    wd
  }

  let(:timezone) { ActiveSupport::TimeZone.new("Europe/Moscow") }

  it "converts time restriction data to an IceCube schedule" do
    sched = Flapjack::Data::Acceptor.
              time_restriction_to_icecube_schedule(weekdays_8_18, timezone)
    expect(sched).not_to be_nil
  end

end
