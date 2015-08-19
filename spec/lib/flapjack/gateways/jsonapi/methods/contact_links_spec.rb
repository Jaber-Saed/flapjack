require 'spec_helper'
require 'flapjack/gateways/jsonapi'

describe 'Flapjack::Gateways::JSONAPI::Methods::ContactLinks', :sinatra => true, :logger => true, :pact_fixture => true do

  include_context "jsonapi"

  let(:contact) { double(Flapjack::Data::Contact, :id => contact_data[:id]) }
  let(:medium)  { double(Flapjack::Data::Medium, :id => email_data[:id]) }
  let(:acceptor)    { double(Flapjack::Data::Acceptor, :id => acceptor_data[:id]) }

  let(:contact_media)  { double('contact_media') }
  let(:contact_acceptors)  { double('contact_acceptors') }

  let(:meta) {
    {
      :pagination => {
        :page        => 1,
        :per_page    => 20,
        :total_pages => 1,
        :total_count => 1
      }
    }
  }

  it 'lists media for a contact' do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Medium).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([medium.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(contact_media).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(contact).to receive(:media).and_return(contact_media)

    contacts = double('contacts', :all => [contact])
    expect(contacts).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => contact.id).and_return(contacts)

    get "/contacts/#{contact.id}/media"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'medium', :id => medium.id}],
      :links => {
        :self    => "http://example.org/contacts/#{contact.id}/relationships/media",
        :related => "http://example.org/contacts/#{contact.id}/media",
      },
      :meta => meta
    ))
  end

  it 'lists acceptors for a contact' do
    expect(Flapjack::Data::Contact).to receive(:lock).
      with(Flapjack::Data::Acceptor).and_yield

    sorted = double('sorted')
    paged  = double('paged')
    expect(paged).to receive(:ids).and_return([acceptor.id])
    expect(sorted).to receive(:page).with(1, :per_page => 20).and_return(paged)
    expect(sorted).to receive(:count).and_return(1)
    expect(contact_acceptors).to receive(:sort).with(:id => :asc).and_return(sorted)
    expect(contact).to receive(:acceptors).and_return(contact_acceptors)

    contacts = double('contacts', :all => [contact])
    expect(contacts).to receive(:empty?).and_return(false)
    expect(Flapjack::Data::Contact).to receive(:intersect).
      with(:id => contact.id).and_return(contacts)

    get "/contacts/#{contact.id}/acceptors"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to be_json_eql(Flapjack.dump_json(
      :data  => [{:type => 'acceptor', :id => acceptor.id}],
      :links => {
        :self    => "http://example.org/contacts/#{contact.id}/relationships/acceptors",
        :related => "http://example.org/contacts/#{contact.id}/acceptors",
      },
      :meta => meta
    ))
  end

end
