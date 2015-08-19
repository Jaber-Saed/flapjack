#!/usr/bin/env ruby

require 'sinatra/base'

module Flapjack
  module Gateways
    class JSONAPI < Sinatra::Base
      module Methods
        module AssociationDelete

          def self.registered(app)
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Headers
            app.helpers Flapjack::Gateways::JSONAPI::Helpers::Miscellaneous

            Flapjack::Gateways::JSONAPI::RESOURCE_CLASSES.each do |resource_class|
              resource = resource_class.short_model_name.plural

              jsonapi_links = if resource_class.respond_to?(:jsonapi_associations)
                resource_class.jsonapi_associations || {}
              else
                {}
              end

              delete_links = jsonapi_links.select {|n, jd|
                jd.delete.is_a?(TrueClass) && :multiple.eql?(jd.number)
              }

              unless delete_links.empty?

                app.class_eval do
                  single = resource.singularize

                  delete_links.each_pair do |link_name, link_data|
                    link_type = link_data.type

                    swagger_path "/#{resource}/{#{single}_id}/relationships/#{link_name}" do
                      operation :delete do
                        key :description, "Remove one or more #{link_name} from a #{single}"
                        key :operationId, "remove_#{single}_#{link_name}"
                        key :consumes, [JSONAPI_MEDIA_TYPE]
                        parameter do
                          key :name, "#{single}_id".to_sym
                          key :in, :path
                          key :description, "Id of a #{single}"
                          key :required, true
                          key :type, :string
                        end
                        parameter do
                          key :name, :data
                          key :in, :body
                          key :description, "#{link_name} to remove from the #{single}"
                          key :required, true
                          schema do
                            key :type, :array
                            items do
                              key :"$ref", "#{link_type}Reference".to_sym
                            end
                          end
                        end
                        response 204 do
                          key :description, ''
                        end
                        # response :default do
                        #   key :description, 'unexpected error'
                        #   schema do
                        #     key :'$ref', :ErrorModel
                        #   end
                        # end
                      end
                    end
                  end
                end

              end

              id_patt = if Flapjack::Data::Tag.eql?(resource_class)
                "\\S+"
              else
                Flapjack::UUID_RE
              end

              assoc_patt = jsonapi_links.keys.map(&:to_s).join("|")

              app.delete %r{^/#{resource}/(#{id_patt})/relationships/(#{assoc_patt})$} do
                resource_id = params[:captures][0]
                assoc_name  = params[:captures][1].to_sym

                halt(404) unless delete_links.has_key?(assoc_name)

                status 204

                assoc = delete_links[assoc_name]

                assoc_ids, _ = wrapped_link_params(:association => assoc)

                halt(err(403, 'No relationship ids')) if assoc_ids.empty?

                resource_class.lock(*assoc.lock_klasses) do
                  resource_obj = resource_class.find_by_id!(resource_id)
                  assoc = resource_obj.send(assoc_name)
                  assoc.remove_ids(*assoc_ids)
                end
              end
            end
          end
        end
      end
    end
  end
end
