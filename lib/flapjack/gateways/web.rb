#!/usr/bin/env ruby

require 'chronic'
require 'chronic_duration'
require 'sinatra/base'
require 'tilt/erb'
require 'uri'

require 'flapjack/gateways/web/middleware/request_timestamp'

require 'flapjack-diner'

require 'flapjack/data/check'

require 'flapjack/utility'

module Flapjack

  module Gateways

    class Web < Sinatra::Base

      set :root, File.dirname(__FILE__)

      use Flapjack::Gateways::Web::Middleware::RequestTimestamp
      use Rack::MethodOverride

      set :sessions, :true

      set :raise_errors, false
      set :protection, except: :path_traversal

      set :views, settings.root + '/web/views'
      set :public_folder, settings.root + '/web/public'

      set :erb, :layout => 'layout.html'.to_sym

      class << self
        def start
          Flapjack.logger.info "starting web - class"

          set :show_exceptions, false
          @show_exceptions = Sinatra::ShowExceptions.new(self)

          if access_log = (@config && @config['access_log'])
            unless File.directory?(File.dirname(access_log))
              raise "Parent directory for log file #{access_log} doesn't exist"
            end

            use Rack::CommonLogger, ::Logger.new(@config['access_log'])
          end

          # session's only used for error message display, so
          session_secret = @config['session_secret']

          use Rack::Session::Cookie, :key => 'flapjack.session',
                                     :path => '/',
                                     :secret => session_secret || SecureRandom.hex(64)

          @api_url = @config['api_url']
          if @api_url.nil?
            raise "'api_url' config must contain a Flapjack API instance address"
          end
          if URI.regexp(['http', 'https']).match(@api_url).nil?
            raise "'api_url' is not a valid http or https URI (#{@api_url})"
          end
          unless @api_url.match(/^.*\/$/)
            Flapjack.logger.info "api_url must end with a trailing '/', setting to '#{@api_url}/'"
            @api_url = "#{@api_url}/"
          end

          Flapjack::Diner.base_uri(@api_url)
          Flapjack::Diner.logger = ::Logger.new('log/flapjack_diner.log')

          # constants won't be exposed to eRb scope
          @default_logo_url = "img/flapjack-2013-notext-transparent-300-300.png"
          @logo_image_file  = nil
          @logo_image_ext   = nil

          if logo_image_path = @config['logo_image_path']
            if File.file?(logo_image_path)
              @logo_image_file = logo_image_path
              @logo_image_ext  = File.extname(logo_image_path)
            else
              Flapjack.logger.error "logo_image_path '#{logo_image_path}'' does not point to a valid file."
            end
          end

          @auto_refresh = (@config['auto_refresh'].respond_to?('to_i') &&
                           (@config['auto_refresh'].to_i > 0)) ? @config['auto_refresh'].to_i : false
        end
      end

      include Flapjack::Utility

      helpers do
        def h(text)
          ERB::Util.h(text)
        end

        def u(text)
          ERB::Util.u(text)
        end

        def include_active?(path)
          return '' unless request.path == "/#{path}"
          " class='active'"
        end

        def charset_for_content_type(ct)
          charset = Encoding.default_external
          charset.nil? ? ct : "#{ct}; charset=#{charset.name}"
        end
      end

      ['config'].each do |class_inst_var|
        define_method(class_inst_var.to_sym) do
          self.class.instance_variable_get("@#{class_inst_var}")
        end
      end

      before do
        content_type charset_for_content_type('text/html')

        @base_url         = "#{request.base_url}/"
        @default_logo_url = self.class.instance_variable_get('@default_logo_url')
        @logo_image_file  = self.class.instance_variable_get('@logo_image_file')
        @logo_image_ext   = self.class.instance_variable_get('@logo_image_ext')
        @auto_refresh     = self.class.instance_variable_get('@auto_refresh')

        input = nil
        query_string = (request.query_string.respond_to?(:length) &&
        request.query_string.length > 0) ? "?#{request.query_string}" : ""
        if Flapjack.logger.debug?
          input = env['rack.input'].read
          Flapjack.logger.debug("#{request.request_method} #{request.path_info}#{query_string} #{input}")
        elsif Flapjack.logger.info?
          input = env['rack.input'].read
          input_short = input.gsub(/\n/, '').gsub(/\s+/, ' ')
          Flapjack.logger.info("#{request.request_method} #{request.path_info}#{query_string} #{input_short[0..80]}")
        end
        env['rack.input'].rewind unless input.nil?
      end

      get '/img/branding.*' do
        halt(404) unless @logo_image_file && params[:splat].first.eql?(@logo_image_ext[1..-1])
        send_file(@logo_image_file)
       end

      get '/' do
        @metrics = Flapjack::Diner.metrics

        erb 'index.html'.to_sym
      end

      get '/self_stats' do
        @current_time = Time.now

        @api_url = self.class.instance_variable_get('@api_url')

        @metrics   = Flapjack::Diner.metrics
        statistics = Flapjack::Diner.statistics

        unless statistics.nil?
          @executive_instances = statistics.each_with_object({}) do |stats, memo|
            if 'global'.eql?(stats[:instance_name])
              @global_stats = stats
              next
            end
            boot_time =  Time.parse(stats[:created_at])
            uptime = @current_time - boot_time
            uptime_string = ChronicDuration.output(uptime, :format => :short,
                              :keep_zero => true, :units => 2) || '0s'

            event_counters = {}
            event_rates    = {}

            [:all_events, :ok_events, :failure_events, :action_events,
             :invalid_events].each do |evt|

              count               = stats[evt]
              event_counters[evt] = count
              event_rates[evt]    = (uptime > 0) ? (count.to_f / uptime).round : nil
            end

            memo[stats[:instance_name]] = {
              :uptime         => uptime,
              :uptime_string  => uptime_string,
              :event_counters => event_counters,
              :event_rates    => event_rates
            }
          end
        end

        erb 'self_stats.html'.to_sym
      end

      get '/tags' do
        opts = {}
        @name = params[:name]
        opts.update(:name => @name) unless @name.nil? || @name.empty?

        @tags = Flapjack::Diner.tags(:filter => opts,
          :page => (params[:page] || 1))

        unless @tags.nil? || @tags.empty?
          @pagination = pagination_from_context(Flapjack::Diner.context)
          unless @pagination.nil?
            @links = create_pagination_links(@pagination[:page],
              @pagination[:total_pages])
          end

          included = Flapjack::Diner.context[:included]

          unless included.nil? || included.empty?

          end
        end

        erb 'tags.html'.to_sym
      end

      get '/tags/:name' do
        tag_name = params[:name]

        @tag = Flapjack::Diner.tags(tag_name, :include => 'checks')
        err(404, "Could not find tag '#{tag_name}'") if @tag.nil?

        included = Flapjack::Diner.context[:included]

        @checks = []

        unless included.nil? || included.empty?
          @checks = some_included_records(@tag[:relationships], :checks,
            included, 'check')
        end

        erb 'tag.html'.to_sym
      end

      get '/checks' do
        time = Time.now

        opts = {}

        @name = params[:name]
        opts.update(:name => @name) unless @name.nil? || @name.empty?

        @enabled = boolean_from_str(params[:enabled])
        opts.update(:enabled => @enabled) unless @enabled.nil?

        @failing = boolean_from_str(params[:failing])
        opts.update(:failing => @failing) unless @failing.nil?

        @checks = Flapjack::Diner.checks(:filter => opts,
                    :page => (params[:page] || 1),
                    :include => ['current_state', 'latest_notifications',
                                 'current_scheduled_maintenances',
                                 'current_unscheduled_maintenance'])

        @states = {}

        unless @checks.nil? || @checks.empty?
          @pagination = pagination_from_context(Flapjack::Diner.context)
          unless @pagination.nil?
            @links = create_pagination_links(@pagination[:page],
              @pagination[:total_pages])
          end

          included = Flapjack::Diner.context[:included]

          unless included.nil? || included.empty?
            @states = @checks.each_with_object({}) do |check, memo|
              memo[check[:id]] = check_state(check, included, time)
            end
          end
        end

        erb 'checks.html'.to_sym
      end

      get '/checks/:id' do
        check_id  = params[:id]

        @current_time = DateTime.now

        # contacts.media will also return contacts, per JSONAPI v1 relationships
        @check = Flapjack::Diner.checks(check_id,
                   :include => ['contacts.media', 'current_state',
                                'latest_notifications',
                                'current_scheduled_maintenances',
                                'current_unscheduled_maintenance'])

        halt(404, "Could not find check '#{check_id}'") if @check.nil?

        included = Flapjack::Diner.context[:included]

        @contacts = []
        @media_by_contact_id = {}

        unless included.nil? || included.empty?
          @state = check_extra_state(@check, included, @current_time)

          @contacts = some_included_records(@check[:relationships], :contacts,
            included, 'contact')

          @media_by_contact_id = @contacts.inject({}) do |memo, contact|
            memo[contact[:id]] = some_included_records(contact[:relationships], :media,
              included, 'medium')
            memo
          end
        end

        # these two requests will only get first page of 20 records, which is what we want
        state_links = Flapjack::Diner.check_link_states(check_id,
          :include => 'states')
        @state_changes = all_included_records(state_links,
          Flapjack::Diner.context[:included], 'state')

        sm_links = Flapjack::Diner.check_link_scheduled_maintenances(check_id,
          :include => 'scheduled_maintenances')

        @scheduled_maintenances = all_included_records(sm_links,
          Flapjack::Diner.context[:included], 'scheduled_maintenance')

        @error = session[:error]; session.delete(:error)

        erb 'check.html'.to_sym
      end

      post "/acknowledgements" do
        summary  = params[:summary]
        check_id = params[:check_id]

        t = Time.now

        dur = ChronicDuration.parse(params[:duration] || '')
        duration = (dur.nil? || (dur <= 0)) ? (4 * 60 * 60) : dur

        # FIXME create with known id, poll a few times and return
        # success/failure in session

        Flapjack::Diner.create_acknowledgements(:summary => summary,
          :duration => duration, :check => check_id)

        err = Flapjack::Diner.last_error
        unless err.nil?
          session[:error] = "Could not create the acknowledgement: #{err}"
        end

        redirect back
      end

      patch '/unscheduled_maintenances/:id' do
        unscheduled_maintenance_id = params[:id]

        Flapjack::Diner.update_unscheduled_maintenances(
          :id => unscheduled_maintenance_id, :end_time => Time.now)

        err = Flapjack::Diner.last_error
        unless err.nil?
          session[:error] = "Could not end unscheduled maintenance: #{err}"
        end

        redirect back
      end

      post '/scheduled_maintenances' do
        check_id  = params[:check_id]

        start_time = Chronic.parse(params[:start_time])
        raise ArgumentError, "start time parsed to nil" if start_time.nil?
        duration   = ChronicDuration.parse(params[:duration])
        summary    = params[:summary]

        Flapjack::Diner.create_scheduled_maintenances(:summary => summary,
          :start_time => start_time, :end_time => (start_time + duration),
          :check => check_id)

        err = Flapjack::Diner.last_error
        unless err.nil?
          Flapjack.logger.info "Could not create scheduled maintenance: #{err}"
          session[:error] = "Could not create scheduled maintenance for the check."
        end

        redirect back
      end

      patch '/checks/:id' do
        check_id = params[:id]

        Flapjack::Diner.update_checks(:id => check_id, :enabled => false)

        err = Flapjack::Diner.last_error
        unless err.nil?
          Flapjack.logger.info "Could not disable check: #{err}"
          session[:error] = "Could not disable the check."
        end

        redirect '/'
      end

      patch '/scheduled_maintenances/:id' do
        scheduled_maintenance_id = params[:id]

        Flapjack::Diner.update_scheduled_maintenances({:id => scheduled_maintenance_id,
          :end_time => Time.now})

        err = Flapjack::Diner.last_error
        unless err.nil?
          Flapjack.logger.info "Could not end scheduled maintenance: #{err}"
          session[:error] = "Could not end scheduled maintenance."
        end

        redirect back
      end

      # FIXME should fail if its start time or end_time is in the past
      # we'll allow the API to delete without fear or favour though
      delete '/scheduled_maintenances/:id' do
        scheduled_maintenance_id = params[:id]

        Flapjack::Diner.delete_scheduled_maintenances(scheduled_maintenance_id)

        err = Flapjack::Diner.last_error
        unless err.nil?
          Flapjack.logger.info "Could not delete scheduled maintenance: #{err}"
          session[:error] = "Could not delete scheduled maintenance."
        end

        redirect back
      end

      get '/contacts' do
        opts = {}
        @name = params[:name]
        opts.update(:name => @name) unless @name.nil?

        @contacts = Flapjack::Diner.contacts(:page => params[:page] || 1,
          :filter => opts, :sort => '+name')

        unless @contacts.nil?
          @pagination = pagination_from_context(Flapjack::Diner.context)
          unless @pagination.nil?
            @links = create_pagination_links(@pagination[:page],
              @pagination[:total_pages])
          end
        end

        erb 'contacts.html'.to_sym
      end

      get "/contacts/:id" do
        contact_id = params[:id]

        @contact = Flapjack::Diner.contacts(contact_id,
          :include => ['acceptors.tags', 'acceptors.media',
                       'checks', 'media.alerting_checks',
                       'rejectors.tags', 'rejectors.media'])
        halt(404, "Could not find contact '#{contact_id}'") if @contact.nil?

        @acceptors = []
        @checks = []
        @media = []
        @rejectors = []

        @alerting_checks_by_media_id = {}

        @tags_by_acceptor_id  = {}
        @media_by_acceptor_id = {}
        @tags_by_rejector_id  = {}
        @media_by_rejector_id = {}

        context = Flapjack::Diner.context
        unless context.nil?
          included = context[:included]
          unless included.nil?
            @acceptors = some_included_records(@contact[:relationships], :acceptors,
              included, 'acceptor')

            unless @acceptors.nil? || @acceptors.empty?
              @tags_by_acceptor_id = @acceptors.inject({}) do |memo, acceptor|
                memo[acceptor[:id]] = some_included_records(acceptor[:relationships], :tags,
                  included, 'tag')
                memo
              end

              @media_by_acceptor_id = @acceptors.inject({}) do |memo, acceptor|
                memo[acceptor[:id]] = some_included_records(acceptor[:relationships], :media,
                  included, 'medium')
                memo
              end
            end

            @checks = some_included_records(@contact[:relationships], :checks,
              included, 'check')
            @media = some_included_records(@contact[:relationships], :media,
              included, 'medium')

            unless @media.nil? || @media.empty?
              @alerting_checks_by_media_id = @media.inject({}) do |memo, medium|
                memo[medium[:id]] = some_included_records(medium[:relationships], :alerting_checks,
                  included, 'check')
                memo
              end
            end

            @rejectors = some_included_records(@contact[:relationships], :rejectors,
              included, 'rejector')

            unless @rejectors.nil? || @rejectors.empty?
              @tags_by_rejector_id = @acceptors.inject({}) do |memo, rejector|
                memo[rejector[:id]] = some_included_records(rejector[:relationships], :tags,
                  included, 'tag')
                memo
              end

              @media_by_rejector_id = @acceptors.inject({}) do |memo, rejector|
                memo[rejector[:id]] = some_included_records(rejector[:relationships], :media,
                  included, 'medium')
                memo
              end
            end
          end
        end

        erb 'contact.html'.to_sym
      end

      error do
        e = env['sinatra.error']
        # trace = e.backtrace.join("\n")
        # puts trace

        # Rack::CommonLogger doesn't log requests which result in exceptions.
        # If you want something done properly, do it yourself...
        access_log = self.class.instance_variable_get('@middleware').detect {|mw|
          mw.first.is_a?(::Rack::CommonLogger)
        }
        unless access_log.nil?
          access_log.first.send(:log, status_code,
            ::Rack::Utils::HeaderHash.new(headers), msg,
            env['request_timestamp'])
        end
        self.class.instance_variable_get('@show_exceptions').pretty(env, e)
      end

    private

      def check_state(check, included, time)
        current_state = some_included_records(check[:relationships], :current_state,
          included, 'state')

        last_changed = if current_state.nil? || current_state[:created_at].nil?
          nil
        else
          begin
            DateTime.parse(current_state[:created_at])
          rescue ArgumentError
            Flapjack.logger.warn("error parsing check state :created_at ( #{current_state.inspect} )")
          end
        end

        last_updated = if current_state.nil? || current_state[:updated_at].nil?
          nil
        else
          begin
            DateTime.parse(current_state[:updated_at])
          rescue ArgumentError
            Flapjack.logger.warn("error parsing check state :updated_at ( #{current_state.inspect} )")
          end
        end

        latest_notifications = some_included_records(check[:relationships], :latest_notifications,
          included, 'state')

        current_scheduled_maintenances = some_included_records(check[:relationships],
          :current_scheduled_maintenances, included, 'scheduled_maintenance')

        current_scheduled_maintenance = current_scheduled_maintenances.max_by do |sm|
          begin
            DateTime.parse(sm[:end_time]).to_i
          rescue ArgumentError
            Flapjack.logger.warn "Couldn't parse time from current_scheduled_maintenances"
            -1
          end
        end

        in_scheduled_maintenance = !current_scheduled_maintenance.nil?

        current_unscheduled_maintenance = some_included_records(check[:relationships],
          :current_unscheduled_maintenance, included, 'unscheduled_maintenance')

        in_unscheduled_maintenance = !current_unscheduled_maintenance.nil?

        {
          :condition     => current_state.nil? ? '-' : current_state[:condition],
          :summary       => current_state.nil? ? '-' : current_state[:summary],
          :latest_notifications => (latest_notifications || []),
          :last_changed  => last_changed,
          :last_updated  => last_updated,
          :in_scheduled_maintenance => in_scheduled_maintenance,
          :in_unscheduled_maintenance => in_unscheduled_maintenance
        }
      end

      def check_extra_state(check, included, time)
        state = check_state(check, included, time)

        current_state = some_included_records(check[:relationships], :current_state,
          included, 'state')

        current_scheduled_maintenances = some_included_records(check[:relationships],
          :current_scheduled_maintenances, included, 'scheduled_maintenance')

        current_scheduled_maintenance = current_scheduled_maintenances.max_by do |sm|
          begin
            DateTime.parse(sm[:end_time]).to_i
          rescue ArgumentError
            Flapjack.logger.warn "Couldn't parse time from current_scheduled_maintenances"
            -1
          end
        end

        current_unscheduled_maintenance = some_included_records(check[:relationships],
          :current_unscheduled_maintenance, included, 'unscheduled_maintenance')

        state.merge(
          :details       => current_state.nil? ? '-' : current_state[:details],
          :perfdata      => current_state.nil? ? '-' : current_state[:perfdata],
          :current_scheduled_maintenances => (current_scheduled_maintenances || []),
          :current_scheduled_maintenance => current_scheduled_maintenance,
          :current_unscheduled_maintenance => current_unscheduled_maintenance,
        )
      end

      def all_included_records(links, included, type)
        case links
        when Array
          # respects the order provided by the main linkage data
          ids = links.inject([]) do |memo, link|
            if type.eql?(link[:type])
              memo << link[:id]
            end
            memo
          end
          included.select {|incl|
            type.eql?(incl[:type]) && ids.include?(incl[:id])
          }.sort_by {|a| ids.index {|i| i == a[:id]}}
        when Hash
          included.detect do |incl|
            type.eql?(incl[:type]) && links[:id].eql?(incl[:id])
          end
        end
      end

      def some_included_records(links, field, included, type)
        return unless links.has_key?(field) && links[field].has_key?(:data) &&
          !links[field][:data].nil?

        if links[field][:data].is_a?(Array)
          ids = links[field][:data].collect {|lr| lr[:id]}
          return [] if ids.empty?

          included.select {|incl|
            type.eql?(incl[:type]) && ids.include?(incl[:id])
          }.sort_by {|a| ids.index {|i| i == a[:id]}}
        else
          id = links[field][:data][:id]
          return if id.nil?

          included.detect do |incl|
            type.eql?(incl[:type]) && id.eql?(incl[:id])
          end
        end
      end

      def pagination_from_context(context)
        ((context || {})[:meta] || {})[:pagination]
      end

      def require_js(*js)
        @required_js ||= []
        @required_js += js
        @required_js.uniq!
      end

      def require_css(*css)
        @required_css ||= []
        @required_css += css
        @required_css.uniq!
      end

      def include_required_js
        return "" if @required_js.nil?
        @required_js.map { |filename|
          "<script type='text/javascript' src='#{link_to("js/#{filename}.js")}'></script>"
        }.join("\n    ")
      end

      def include_required_css
        return "" if @required_css.nil?
        @required_css.map { |filename|
          %(<link rel="stylesheet" href="#{link_to("css/#{filename}.css")}" media="screen">)
        }.join("\n    ")
      end

      # from http://gist.github.com/98310
      def link_to(url_fragment, mode=:path_only)
        case mode
        when :path_only
          base = @base_url
        when :full_url
          if (request.scheme == 'http' && request.port == 80 ||
              request.scheme == 'https' && request.port == 443)
            port = ""
          else
            port = ":#{request.port}"
          end
          base = "#{request.scheme}://#{request.host}#{port}#{request.script_name}"
        else
          raise "Unknown script_url mode #{mode}"
        end
        "#{base}#{url_fragment}"
      end

      def page_title(string)
        @page_title = string
      end

      def include_page_title
        @page_title ? "#{@page_title} | Flapjack" : "Flapjack"
      end

      def boolean_from_str(str)
        case str
        when '0', 'f', 'false', 'n', 'no'
          false
        when '1', 't', 'true', 'y', 'yes'
          true
        end
      end

      def create_pagination_links(page, total_pages)
        pages = {}
        pages[:first] = 1
        pages[:prev]  = page - 1 if (page > 1)
        pages[:next]  = page + 1 if page < total_pages
        pages[:last]  = total_pages

        url_without_params = request.url.split('?').first

        links = {}
        pages.each do |key, value|
          page_params = {'page' => value }
          new_params = request.params.merge(page_params)
          links[key] = "#{url_without_params}?#{new_params.to_query}"
        end
        links
      end
    end
  end
end
