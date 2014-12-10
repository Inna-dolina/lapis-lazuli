#
# LapisLazuli
# https://github.com/spriteCloud/lapis-lazuli
#
# Copyright (c) 2013-2014 spriteCloud B.V. and other LapisLazuli contributors.
# All rights reserved.
#
require "json"
require "singleton"
require "securerandom"
require "lapis_lazuli/logger"
require "lapis_lazuli/scenario"
require "lapis_lazuli/browser"
require "lapis_lazuli/options"

module LapisLazuli
  ##
  # Lapis Lazuli class that handles everything
  #
  # Singleton class so that you can get the configuration everywhere
  #
  # Example
  # ll = LapisLazuli::LapisLazuli.instance
  # ll.config("default_env")
  # ll.browser.goto("http://www.spritecloud.com")
  # ll.log.debug("LL example")
  # ll.scenario.id
  class LapisLazuli
    include Singleton
    # Loaded configuration file
    @config
    # Current environment
    @env
    # session key
    @uuid
    attr_reader :log, :scenario, :time
    attr_accessor :scenario, :time, :browser

    ##
    # Initialize of the singleton. Only called once
    # Sets the env to TEST_ENV and populates time with starttime
    def initialize
      if ENV["TEST_ENV"]
        @env = ENV["TEST_ENV"]
      end
      time = Time.now

      @time = {
        :timestamp => time.strftime('%y%m%d_%H%M%S'),
        :epoch => time.to_i.to_s
      }

      @uuid = SecureRandom.hex

      # Current scenario information
      @scenario = Scenario.new
    end

    ##
    # Loads a configuration file, creates a logger and scenario information
    def init(config_name)
      # Load the configuration file
      self.load_config(config_name)

      # We should have a config
      if @config.nil?
        raise "Could not load a configuration"
      end

      # Make log directory
      dir = self.env_or_config('log_dir')
      begin
        Dir.mkdir dir
      rescue SystemCallError => ex
        # Swallow this error; it occurs (amongst other situations) when the
        # directory exists. Checking for an existing directory beforehand is
        # not concurrency safe.
      end

      # Start the logger with the config filename
      log_file = "#{dir}#{File::SEPARATOR}#{File.basename(config_name, ".*")}.log"
      # Or a filename from the environment
      if self.has_env_or_config?("log_file")
        log_file = self.env_or_config("log_file")
      end
      @log = TeeLogger.new(log_file)
      @log.level = self.env_or_config("log_level")
    end

    ##
    # Loads a config based on a filename
    #
    # Supports: YML, JSON
    #
    # Example:
    #   ENV['TEST_ENV'] = 'production'
    #   load_config("config/config.yml")
    #
    # Will try to load the following files:
    # - config/config-production.yml
    # - config/config-debug.yml
    # - config/config-test.yml
    # - config/config-local.yml
    # - config/config.yml
    def load_config(config_name)
      # Split the filename
      ext = File.extname(config_name)
      dir, filename = File.split(config_name)
      basename = File.basename(filename, ext)

      # What are the suffixes to check
      suffixes = [
        "debug",
        "test",
        "local"
      ]

      # Do we have an environment
      if not @env.nil?
        # Add it to the suffixes
        suffixes.unshift(@env)
      end

      # For each suffix
      suffixes.each do |suffix|
        begin
          # Try to load a config file
          self.load_config_from_file("#{dir}/#{basename}-#{suffix}#{ext}")
        rescue
          # Do nothing, load the next file
        end

        # Stop if we have a config
        if @config
          break
        end
      end

      # Try to load the original filename if we don't have a config
      if @config.nil?
        load_config_from_file(config_name)
      end
    end

    ##
    # Loads a config file
    #
    # Supports: YML, JSON
    #
    # Throws errors if:
    # - Config file isn't readable
    # - Environment doesn't exist in config
    # - Default environment not set in config if no environment is set
    def load_config_from_file(filename)
      # Try to load the file from disk
      begin
        # Determine the extension
        ext = File.extname(filename)
        # Use the correct loader
        if ext == ".yml"
          @config = YAML.load_file(filename)
        elsif ext == ".json"
          json = File.read(filename)
          @config = JSON.parse(json)
        end
      rescue RuntimeError => err
        # Can't help you
        raise "Error loading file: #{filename} #{err}"
      end

      # If we have an environment this config should have it
      if @env and not self.has_config?(@env)
        raise "Environment doesn't exist in config file"
      end

      # If we don't have one then load the default
      if @env.nil? and self.has_config?("default_env")
        env = self.config("default_env")
        if self.has_config?(env)
          @env = env
        else
          # We need a config...
          raise "Default environment not present in config file"
        end
      end
    end

    ##
    # Does the config have a variable?
    # Uses config and catches any errors it raises
    def has_config?(variable)
        begin
          value = self.config(variable)
          return (not value.nil?)
        rescue
          return false
        end
    end

    ##
    # Get the configuration from the config,
    # uses a dot seperator for object traversing
    #
    # Example:
    # ll.config("test.google.url") => "www.google.com"
    #
    # Raises error if traversing the object is impossible
    def config(variable=false, default=nil)
      # No variable given? Return the entire object.
      result = @config
      if not variable
        return result
      end

      # Environment variables for known options override the option.
      if CONFIG_OPTIONS.has_key? variable
        env = variable.upcase
        if ENV.has_key? env
          return ENV[env]
        end
      end

      # Otherwise try to find it in the configuration object
      variable.split(".").each do |part|
        if default.nil? and result.nil?
          raise "Unknown configuration variable '#{variable}' and no default given!"
        end
        result = result[part]
      end

      if default.nil? and result.nil?
        if CONFIG_OPTIONS.has_key? variable
          return CONFIG_OPTIONS[variable][0]
        else
          raise "Unknown configuration variable '#{variable}' and no default given!"
        end
      else
        return result || default
      end
    end

    ##
    # Does the environment have a certain config variable
    def has_env?(variable)
      if @env.nil?
        return false
      end
      return self.has_config?("#{@env}.#{variable}")
    end

    ##
    # Get a environment variable from the config file
    # Alias for ll.config(ll.env + "." + variable)
    def env(variable=false, default=nil)
      if not variable
        return self.config(@env)
      end
      return self.config("#{@env}.#{variable}",default)
    end

    ##
    # Checks if a variabl exist in the env or config
    def has_env_or_config?(variable)
      return self.has_env?(variable) || self.has_config?(variable)
    end

    ##
    # Get a variable from the config
    # First checks the environment section, before it checks the global part
    def env_or_config(variable, default=nil)
      if self.has_env?(variable)
        return self.env(variable, default)
      elsif self.has_config?(variable)
        return self.config(variable, default)
      else
        return nil
      end
    end

    ##
    # Checks if there is a browser started
    def has_browser?
      return !@browser.nil?
    end

    ##
    # Get the current main browser
    def browser(*args)
      if @browser.nil?
        # Add LL to the arguments for the browser
        browser_args = args.unshift(self)
        # Create a new browser object
        @browser = Browser.send(:new, *browser_args)
      end
      return @browser
    end

    ##
    # Throw an error based on some settings
    #
    # Examples:
    # ll.error("Simple message") => "Simple message"
    # ll.error(:message => "Simple message") => "Simple message"
    # ll.error(:env => "test") => "Environment setting 'test' not found"
    # ll.error(:env => "test", :exists => true) => "Environment setting 'test' found"
    # ll.error(:screenshot => true, :message => "Simple") => "Simple", and screenshot is taken with the message name included.
    def error(settings=nil)
      # Default message
      message = nil
      groups = nil
      # Do we have settings
      if not settings.nil?
        # Simple string input
        if settings.is_a? String
          message = settings
        elsif settings.is_a? Hash
          if settings.has_key? :message
            message = settings[:message]
          end
          # Environment errors
          if settings.has_key? :env
            # Does the value exist or not?
            exists = ""
            if not (settings.has_key?(:exists) or settings[:exists])
              exists = ' not'
            end
            message = "Environment setting '#{settings[:env]}'" +
                      exists + " found"
          end

          if settings.has_key? :scenario
            message = "Scenario failed: #{settings[:scenario]}"
          elsif settings.has_key? :not_found
            message = "Not found: #{settings[:not_found]}"
          end

          # Grouping of errors
          if settings.has_key? :groups
            grouping = settings[:groups]
            if grouping.is_a? String
              groups = [grouping]
            elsif grouping.is_a? Array
              groups = grouping
            end
          end
        end
      end

      # Exception message shouldn't get lost
      if settings.has_key? :exception and not settings[:exception].nil?
        if message.nil?
          message = settings[:exception].message
        else
          message = "#{message} - #{settings[:exception].message}"
        end
      elsif message.nil?
        message = "An unknown error occurred."
      end

      # Include URL if we have a browser
      if self.has_browser?
        message += " (#{self.browser.url})"
      end

      # Add the groups to the message
      if not groups.nil?
        message = "[#{groups.join("][")}] #{message}"
      end

      # Write the error to the log
      if self.log
        self.log.error(message)
      end

      # Take screenshot, if necessary
      if settings.has_key? :screenshot and settings[:screenshot]
        self.browser.take_screenshot(message)
      end

      # Start debugger, if necessary
      if self.env_or_config("breakpoint_on_error")
        self.start_debugger
      end

      # Raise the message
      if settings.has_key? :exception and not settings[:exception].nil?
        ex = settings[:exception]
        # message already contains ex.message here - or it should
        raise ex.class, message, ex.backtrace
      else
        raise message
      end
    end

    ##
    # Update the variable with timestamps
    def variable(string)
      email_domain = "spriteymail.net"
      if self.has_env_or_config?("email_domain")
        email_domain = self.env_or_config("email_domain")
      end
      random_uuid = SecureRandom.hex
      string % {
        :epoch => @time[:epoch],
        :timestamp => @time[:timestamp],
        :uuid => @uuid,
        :email => "test_#{@uuid}@#{email_domain}",
        :scenario_id => @scenario.id,
        :scenario_epoch => @scenario.time[:epoch],
        :scenario_timestamp => @scenario.time[:timestamp],
        :scenario_email => "test_#{@uuid}_scenario_#{@scenario.uuid}@#{email_domain}",
        :scenario_uuid => @scenario.uuid,
        :random => rand(9999),
        :random_small => rand(99),
        :random_lange => rand(999999),
        :random_uuid => random_uuid,
        :random_email => "test_#{@uuid}_random_#{random_uuid}@#{email_domain}"
      }
    end

    ##
    # Same as variable, but modify the string.
    def variable!(string)
      string.replace(self.variable(string))
    end

    ##
    # If byebug (ruby >= 2.0) or debugger (ruby < 2.0) are installed, start
    # the debugger now.
    def start_debugger
      # First try the more modern 'byebug'
      begin
        require "byebug"
        byebug
      rescue LoadError
        # If that fails, try the older debugger
        begin
          require 'debugger'
          debugger
        rescue LoadError
          self.log.info "No debugger found, can't break on failures."
        end
      end
    end

    ##
    # Hook invoked in AfterConfiguration
    def after_configuration(config)
      config.options[:formats] << ["LapisLazuli::Formatter", STDERR]
    end

    ##
    # Hook invoked in BeforeScenario
    def before_scenario(scenario)
      # Update the scenario informaton
      self.scenario.running = true
      self.scenario.update(scenario)
      # Show the name
      self.log.info("Starting Scenario: #{self.scenario.id}")
    end

    ##
    # Hook invoked in AfterScenario
    def after_scenario(scenario)
      # The current scenario has finished
      self.scenario.running = false

      # Sleep if needed
      if self.has_env_or_config?("step_pause_time")
        sleep self.env_or_config("step_pause_time")
      end

      # Did we fail?
      if (scenario.failed? or (self.scenario.check_browser_errors and self.browser.has_error?))
        # Take a screenshot if needed
        if self.has_env_or_config?('screenshot_on_failure')
          self.browser.take_screenshot()
        end
      end
      # Close browser if needed
      self.browser.close_after_scenario(scenario)
    end
  end
end
