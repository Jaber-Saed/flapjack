#!/usr/bin/env ruby

require 'active_model'
require 'swagger/blocks'

require 'zermelo/records/stub'

require 'flapjack/data/extensions/associations'
require 'flapjack/data/extensions/short_name'

require 'flapjack/data/event'

module Flapjack
  module Data
    class TestNotification

      include Swagger::Blocks

      include Zermelo::Records::Stub
      include ActiveModel::Serializers::JSON
      self.include_root_in_json = false

      include Flapjack::Data::Extensions::Associations
      include Flapjack::Data::Extensions::ShortName

      define_attributes :summary => :string

      attr_accessor :queue

      def save!
        @id ||= SecureRandom.uuid
        @saved = true
      end

      def persisted?
        !@id.nil? && @saved.is_a?(TrueClass)
      end

      def check=(c)
        raise "Test notification not saved" unless persisted?
        raise "Test notification queue not set" if @queue.nil? || @queue.empty?
        raise "Test notification already sent" if @sent

        Flapjack::Data::Event.test_notifications(
          @queue, [c], :summary => self.summary
        )

        @sent = true
      end

      def tag=(t)
        raise "Test notification not saved" unless persisted?
        raise "Test notification queue not set" if @queue.nil? || @queue.empty?
        raise "Test notification already sent" if @sent

        checks = t.checks

        unless checks.empty?
          Flapjack::Data::Event.test_notifications(
            @queue, checks.all, :summary => self.summary
          )
        end

        @sent = true
      end

      swagger_schema :TestNotification do
        key :required, [:id, :type]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::TestNotification.short_model_name.singular]
        end
        property :summary do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :TestNotificationLinks
        end
      end

      swagger_schema :TestNotificationLinks do
        # create (and response) can only have one of these set
        property :check do
          key :"$ref", :CheckLinkage
        end
        property :tag do
          key :"$ref", :TagLinkage
        end
      end

      swagger_schema :TestNotificationCreate do
        key :required, [:type, :summary]
        property :id do
          key :type, :string
          key :format, :uuid
        end
        property :type do
          key :type, :string
          key :enum, [Flapjack::Data::TestNotification.short_model_name.singular]
        end
        property :summary do
          key :type, :string
        end
        property :relationships do
          key :"$ref", :TestNotificationCreateLinks
        end
      end

      swagger_schema :TestNotificationCreateLinks do
        # create (and response) can only have one of these set
        property :check do
          key :"$ref", :data_CheckReference
        end
        property :tag do
          key :"$ref", :data_TagReference
        end
      end

      def self.swagger_included_classes
        # hack -- hardcoding for now
        []
      end

      def self.jsonapi_methods
        @jsonapi_methods ||= {
          :post => Flapjack::Gateways::JSONAPI::Data::MethodDescriptor.new(
            :attributes => [:summary],
            :description => " "
          )
        }
      end

      def self.jsonapi_associations
        unless instance_variable_defined?('@jsonapi_associations')
          @jsonapi_associations = {
            :check => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true,
              :number => :singular, :link => false, :includable => false,
              :type => 'check',
              :klass => Flapjack::Data::Check,
              :descriptions => {
                :post => " "
              }
            ),
            :tag => Flapjack::Gateways::JSONAPI::Data::JoinDescriptor.new(
              :post => true,
              :number => :singular, :link => false, :includable => false,
              :type => 'tag',
              :klass => Flapjack::Data::Tag,
              :descriptions => {
                :post => " "
              }
            )
          }
          populate_association_data(@jsonapi_associations)
        end
        @jsonapi_associations
      end
    end
  end
end
