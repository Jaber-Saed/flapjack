require 'flapjack/gateways/aws_sns'
require 'flapjack/gateways/email'
require 'flapjack/gateways/sms_messagenet'
require 'flapjack/gateways/sms_nexmo'

def find_or_create_contact(contact_data)
  contact = Flapjack::Data::Contact.intersect(:name => contact_data[:name]).all.first
  if contact.nil?
    contact = Flapjack::Data::Contact.new(:name => contact_data[:name])
    expect(contact.save).to be true
  end

  contact
end

def find_or_create_check(check_data)
  check = Flapjack::Data::Check.intersect(:name => check_data[:name]).all.first

  if check.nil?
    check = Flapjack::Data::Check.new(:name => check_data[:name], :enabled => true)
    expect(check.save).to be true

    entity_name, check_name = check_data[:name].split(':', 2)

    tags = entity_name.split('.', 2).map(&:downcase) +
      check_name.split(' ').map(&:downcase)

    tags = tags.collect do |tag_name|
      Flapjack::Data::Tag.lock do
        tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
        if tag.nil?
          tag = Flapjack::Data::Tag.new(:name => tag_name)
          expect(tag.save).to be true
        end
        tag
      end
    end
    check.tags.add(*tags) unless tags.empty?
  end

  check
end

Given /^the following contacts exist:$/ do |contacts|
  contacts.hashes.each do |contact_data|
    contact = Flapjack::Data::Contact.find_by_id(contact_data['id'])
    expect(contact).to be nil
    contact = Flapjack::Data::Contact.new(
      :id       => contact_data['id'],
      :name     => contact_data['name'],
      :timezone => contact_data['timezone']
    )
    expect(contact.save).to be true
  end
end

Given /^the following checks exist:$/ do |checks|
  checks.hashes.each do |check_data|
    check = Flapjack::Data::Check.find_by_id(check_data['id'])
    expect(check).to be nil

    check = Flapjack::Data::Check.new(
      :id   => check_data['id'],
      :name => check_data['name'],
      :enabled => true
    )
    expect(check.save).to be true

    unless check_data['tags'].nil? || check_data['tags'].strip.empty?
      tags = check_data['tags'].split(',').map(&:strip).collect do |tag_name|
        Flapjack::Data::Tag.lock do
          tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
          if tag.nil?
            tag = Flapjack::Data::Tag.new(:name => tag_name)
            tag.save
          end
          tag
        end
      end
      check.tags.add(*tags) unless tags.empty?
    end
  end
end

Given /^the following media exist:$/ do |media|
  media.hashes.each do |medium_data|
    contact = Flapjack::Data::Contact.find_by_id(medium_data['contact_id'])
    expect(contact).not_to be nil

    medium = Flapjack::Data::Medium.find_by_id(medium_data['id'])
    expect(medium).to be nil
    medium = Flapjack::Data::Medium.new(
      :id               => medium_data['id'],
      :transport        => medium_data['transport'],
      :address          => medium_data['address'],
      :interval         => medium_data['interval'].to_i * 60,
      :rollup_threshold => medium_data['rollup_threshold'].to_i
    )
    expect(medium.save).to be true
    contact.media << medium
  end
end

Given /^the following acceptors exist:$/ do |acceptors|
  acceptors.hashes.each do |acceptor_data|
    contact = Flapjack::Data::Contact.find_by_id(acceptor_data['contact_id'])
    expect(contact).not_to be nil

    time_zone = contact.time_zone
    expect(time_zone).to be_an ActiveSupport::TimeZone

    acceptor = Flapjack::Data::Acceptor.find_by_id(acceptor_data['id'])
    expect(acceptor).to be nil

    conditions = acceptor_data['condition'].split(',').map(&:strip).join(',')

    acceptor = Flapjack::Data::Acceptor.new(
      :id              => acceptor_data['id'],
      :name            => acceptor_data['name'],
      :all             => ['1', 't', 'true', 'y', 'yes'].include?((acceptor_data['all'] || '').strip.downcase),
      :conditions_list => conditions.empty? ? nil : conditions
    )

    unless acceptor_data['time_restrictions'].nil? || acceptor_data['time_restrictions'].strip.empty?
      acceptor.time_restrictions = acceptor_data['time_restrictions'].split(',').map(&:strip).inject([]) do |memo, tr|
        case tr
        when '8-18 weekdays'
          weekdays_8_18 = IceCube::Schedule.new(time_zone.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
          weekdays_8_18.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
          memo << icecube_schedule_to_time_restriction(weekdays_8_18, time_zone)
        end
        memo
      end
    end

    expect(acceptor.save).to be true

    contact.acceptors << acceptor

    unless acceptor_data['tags'].nil? || acceptor_data['tags'].strip.empty?
      tags = acceptor_data['tags'].split(',').map(&:strip).collect do |tag_name|
        Flapjack::Data::Tag.lock do
          tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
          if tag.nil?
            tag = Flapjack::Data::Tag.new(:name => tag_name)
            expect(tag.save).to be true
          end
          tag
        end
      end
      acceptor.tags.add(*tags) unless tags.empty?
    end

    unless acceptor_data['media_ids'].nil? || acceptor_data['media_ids'].strip.empty?
      media_ids = acceptor_data['media_ids'].split(',').map(&:strip)
      media = Flapjack::Data::Medium.find_by_ids(*media_ids)
      expect(media.map(&:id)).to match_array(media_ids)
      acceptor.media.add(*media) unless media.empty?
    end
  end
end

Given /^the following rejectors exist:$/ do |rejectors|
  rejectors.hashes.each do |rejector_data|
    contact = Flapjack::Data::Contact.find_by_id(rejector_data['contact_id'])
    expect(contact).not_to be nil

    time_zone = contact.time_zone
    expect(time_zone).to be_an ActiveSupport::TimeZone

    rejector = Flapjack::Data::Rejector.find_by_id(rejector_data['id'])
    expect(rejector).to be nil

    conditions = rejector_data['condition'].split(',').map(&:strip).join(',')

    rejector = Flapjack::Data::Rejector.new(
      :id              => rejector_data['id'],
      :name            => rejector_data['name'],
      :all             => ['1', 't', 'true', 'y', 'yes'].include?((rejector_data['all'] || '').strip.downcase),
      :conditions_list => conditions.empty? ? nil : conditions
    )

    unless rejector_data['time_restrictions'].nil? || rejector_data['time_restrictions'].strip.empty?
      rejector.time_restrictions = rejector_data['time_restrictions'].split(',').map(&:strip).inject([]) do |memo, tr|
        case tr
        when '8-18 weekdays'
          weekdays_8_18 = IceCube::Schedule.new(time_zone.local(2013,2,1,8,0,0), :duration => 60 * 60 * 10)
          weekdays_8_18.add_recurrence_rule(IceCube::Rule.weekly.day(:monday, :tuesday, :wednesday, :thursday, :friday))
          memo << icecube_schedule_to_time_restriction(weekdays_8_18, time_zone)
        end
        memo
      end
    end

    expect(rejector.save).to be true

    contact.rejectors << rejector

    unless rejector_data['tags'].nil? || rejector_data['tags'].strip.empty?
      tags = rejector_data['tags'].split(',').map(&:strip).collect do |tag_name|
        Flapjack::Data::Tag.lock do
          tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
          if tag.nil?
            tag = Flapjack::Data::Tag.new(:name => tag_name)
            expect(tag.save).to be true
          end
          tag
        end
      end
      rejector.tags.add(*tags) unless tags.empty?
    end

    unless rejector_data['media_ids'].nil? || rejector_data['media_ids'].strip.empty?
      media_ids = rejector_data['media_ids'].split(',').map(&:strip)
      media = Flapjack::Data::Medium.find_by_ids(*media_ids)
      expect(media.map(&:id)).to match_array(media_ids)
      rejector.media.add(*media) unless media.empty?
    end
  end
end

Given /^(?:a|the) user wants to receive SMS alerts for check '(.+)'$/ do |check_name|
  contact = find_or_create_contact(:name => 'John Smith')

  sms = Flapjack::Data::Medium.new(:transport => 'sms',
    :address => '+61888888888', :interval => 600)
  expect(sms.save).to be true
  contact.media << sms

  check = find_or_create_check(:name => check_name)

  acceptor = Flapjack::Data::Acceptor.new(:conditions_list => 'critical')
  expect(acceptor.save).to be true

  contact.acceptors << acceptor

  Flapjack::Data::Tag.lock( Flapjack::Data::Check, Flapjack::Data::Acceptor) do

    tags = check_name.gsub(/\./, '_').split(':', 2).collect do |tag_name|
      Flapjack::Data::Tag.lock do
        tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
        if tag.nil?
          tag = Flapjack::Data::Tag.new(:name => tag_name)
          expect(tag.save).to be true
        end
        tag
      end
    end
    acceptor.tags.add(*tags) unless tags.empty?
    check.tags.add(*tags) unless tags.empty?
  end

  acceptor.media << sms
end

Given /^(?:a|the) user wants to receive Nexmo alerts for check '(.+)'$/ do |check_name|
  contact = find_or_create_contact(:name => 'John Smith')

  nexmo = Flapjack::Data::Medium.new(:transport => 'sms_nexmo',
    :address => '+61888888888', :interval => 600)
  expect(nexmo.save).to be true
  contact.media << nexmo

  check = find_or_create_check(:name => check_name)

  acceptor = Flapjack::Data::Acceptor.new(:conditions_list => 'critical')
  expect(acceptor.save).to be true

  contact.acceptors << acceptor

  Flapjack::Data::Tag.lock( Flapjack::Data::Check, Flapjack::Data::Acceptor) do
    tags = check_name.gsub(/\./, '_').split(':', 2).collect do |tag_name|
      tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
      if tag.nil?
        tag = Flapjack::Data::Tag.new(:name => tag_name)
        expect(tag.save).to be true
      end
      tag
    end
    acceptor.tags.add(*tags)
    check.tags.add(*tags)
  end

  acceptor.media << nexmo
end

Given /^(?:a|the) user wants to receive email alerts for check '(.+)'$/ do |check_name|
  contact = find_or_create_contact(:name => 'Jane Smith')

  email = Flapjack::Data::Medium.new(:transport => 'email',
    :address => 'janes@example.dom', :interval => 600)
  expect(email.save).to be true
  contact.media << email

  check = find_or_create_check(:name => check_name)

  acceptor = Flapjack::Data::Acceptor.new(:conditions_list => 'critical')
  expect(acceptor.save).to be true

  contact.acceptors << acceptor

  Flapjack::Data::Tag.lock( Flapjack::Data::Check, Flapjack::Data::Acceptor) do
    tags = check_name.gsub(/\./, '_').split(':', 2).collect do |tag_name|
      Flapjack::Data::Tag.lock do
        tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
        if tag.nil?
          tag = Flapjack::Data::Tag.new(:name => tag_name)
          expect(tag.save).to be true
        end
        tag
      end
    end
    acceptor.tags.add(*tags) unless tags.empty?
    check.tags.add(*tags) unless tags.empty?
  end

  acceptor.media << email
end

Given /^(?:a|the) user wants to receive SNS alerts for check '(.+)'$/ do |check_name|
  contact = find_or_create_contact(:name => 'James Smithson')

  sns = Flapjack::Data::Medium.new(:transport => 'sns',
    :address => 'arn:aws:sns:us-east-1:698519295917:My-Topic', :interval => 600)
  expect(sns.save).to be true
  contact.media << sns

  check = find_or_create_check(:name => check_name)

  acceptor = Flapjack::Data::Acceptor.new(:conditions_list => 'critical')
  expect(acceptor.save).to be true

  contact.acceptors << acceptor

  Flapjack::Data::Tag.lock( Flapjack::Data::Check, Flapjack::Data::Acceptor) do
    tags = check_name.gsub(/\./, '_').split(':', 2).collect do |tag_name|
      Flapjack::Data::Tag.lock do
        tag = Flapjack::Data::Tag.intersect(:name => tag_name).all.first
        if tag.nil?
          tag = Flapjack::Data::Tag.new(:name => tag_name)
          expect(tag.save).to be true
        end
        tag
      end
    end
    acceptor.tags.add(*tags) unless tags.empty?
    check.tags.add(*tags) unless tags.empty?
  end

  acceptor.media << sns
end

When /^an event notification is generated for check '(.+)'$/ do |check_name|
  timestamp = Time.now

  event = Flapjack::Data::Event.new('state'   => 'critical',
                                    'summary' => '100% packet loss',
                                    'entity'  => check_name.split(':', 2).first,
                                    'check'   => check_name.split(':', 2).last,
                                    'time'    => timestamp)

  Flapjack::Data::Check.lock(Flapjack::Data::State, Flapjack::Data::Notification) do

    check = Flapjack::Data::Check.intersect(:name => check_name).all.first
    expect(check).not_to be_nil

    state = Flapjack::Data::State.new(:created_at => timestamp, :updated_at => timestamp,
      :condition => 'critical')
    state.save
    check.states << state
    check.most_severe = state

    notification = Flapjack::Data::Notification.new(
      :condition_duration  => 0.0,
      :severity            => 'critical',
      :duration            => event.duration,
    )

    unless notification.save
      raise "Couldn't save notification: #{notification.errors.full_messages.inspect}"
    end

    notification.state = state
    check.notifications << notification
    @notifier.instance_variable_get('@queue').push(notification)
  end

  drain_notifications
end

Then /^an? (SMS|Nexmo|SNS|email) alert for check '(.+)' should( not)? be queued$/ do |medium, check_name, neg|
  med = case medium
  when 'Nexmo'
    'sms_nexmo'
  else
    medium.downcase
  end
  queue = redis_peek("#{med}_notifications", Flapjack::Data::Alert)
  expect(queue.select {|n| n.check.name == check_name }).
        send((neg ? :to : :not_to), be_empty)
end

Given /^an? (SMS|Nexmo|SNS|email) alert has been queued for check '(.+)'$/ do |media_transport, check_name|
  check = Flapjack::Data::Check.intersect(:name => check_name).all.first
  expect(check).not_to be_nil

  @alert = Flapjack::Data::Alert.new(
    :condition => 'critical',
    :condition_duration => 15.0,
    :time => Time.now)

  unless @alert.save
    raise "Couldn't save alert: #{@alert.errors.full_messages.inspect}"
  end

  med = case media_transport
  when 'Nexmo'
    'sms_nexmo'
  else
    media_transport.downcase
  end

  medium = Flapjack::Data::Medium.intersect(:transport => med).all.first
  expect(medium).not_to be_nil

  medium.alerts << @alert
  check.alerts << @alert
end

# TODO may need to get more complex, depending which SMS provider is used
When /^the SMS alert handler runs successfully$/ do
  @request = stub_request(:get, /^#{Regexp.escape('https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage')}/)
  @sms = Flapjack::Gateways::SmsMessagenet.new(:config => {'username' => 'abcd', 'password' => 'efgh'})
  @sms.send(:handle_alert, @alert)
end

When /^the SMS alert handler fails to send an SMS$/ do
  @request = stub_request(:get, /^#{Regexp.escape('https://www.messagenet.com.au/dotnet/Lodge.asmx/LodgeSMSMessage')}/).to_return(:status => [500, "Internal Server Error"])
  @sms = Flapjack::Gateways::SmsMessagenet.new(:config => {'username' => 'abcd', 'password' => 'efgh'})
  @sms.send(:handle_alert, @alert)
end

When /^the Nexmo alert handler runs successfully$/ do
  @request = stub_request(:post, /^#{Regexp.escape('https://rest.nexmo.com/sms/json')}/).
    to_return(:headers => {'Content-type' => 'application/json'},
              :body => Flapjack.dump_json(:messages => [{:status => '0', :'message-id' => 'abc'}]))
  @sms_nexmo = Flapjack::Gateways::SmsNexmo.new(:config => {'api_key' => 'THEAPIKEY', 'secret' => 'secret', 'from' => 'someone'})
  @sms_nexmo.send(:handle_alert, @alert)
end

When /^the email alert handler runs successfully$/ do
  @email = Flapjack::Gateways::Email.new(:config => {'smtp_config' => {'host' => '127.0.0.1', 'port' => 2525, 'from' => 'flapjack@example.com'}})
  @email.send(:handle_alert, @alert)
end

When /^the email alert handler fails to send an email$/ do
  module Mail
    class TestMailer
      alias_method :"orig_deliver!", :"deliver!"
      def deliver!(mail); raise RuntimeError.new; end
    end
  end

  @email = Flapjack::Gateways::Email.new(:config => {'smtp_config' => {'host' => '127.0.0.1', 'port' => 2525, 'from' => 'flapjack@example.com'}})
  begin
    @email.send(:handle_alert, @alert)
  rescue RuntimeError
  end

  module Mail
    class TestMailer
      alias_method :"deliver!", :"orig_deliver!"
    end
  end
end

When /^the SNS alert handler runs successfully$/ do
  @request = stub_request(:post, /amazonaws\.com/)
  @sns = Flapjack::Gateways::AwsSns.new(:config => {
    'access_key' => "AKIAIOSFODNN7EXAMPLE",
    'secret_key' => "secret"})
  @sns.send(:handle_alert, @alert)
end

When /^the SNS alert handler fails to send an SMS$/ do
  @request = stub_request(:post, /amazonaws\.com/).to_return(:status => [500, "Internal Server Error"])
  @sns = Flapjack::Gateways::AwsSns.new(:config => {
    'access_key' => "AKIAIOSFODNN7EXAMPLE",
    'secret_key' => "secret"})
  @sns.send(:handle_alert, @alert)
end

Then /^the user should receive an SMS alert$/ do
  expect(@request).to have_been_requested
  expect(@sms.sent).to eq(1)
end

Then /^the user should receive an SNS alert$/ do
  expect(@request).to have_been_requested
  expect(@sns.sent).to eq(1)
end

Then /^the user should receive a Nexmo alert$/ do
  expect(@request).to have_been_requested
  expect(@sms_nexmo.sent).to eq(1)
end

Then /^the user should receive an email alert$/ do
  expect(Mail::TestMailer.deliveries.length).to eq(1)
  expect(@email.sent).to eq(1)
end

Then /^the user should not receive an SMS alert$/ do
  expect(@request).to have_been_requested
  expect(@sms.sent).to eq(0)
end

Then /^the user should not receive an SNS alert$/ do
  expect(@request).to have_been_requested
  expect(@sns.sent).to eq(0)
end

Then /^the user should not receive an email alert$/ do
  expect(Mail::TestMailer.deliveries).to be_empty
  expect(@email.sent).to eq(0)
end
