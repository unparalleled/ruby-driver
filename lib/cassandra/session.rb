# encoding: utf-8

#--
# Copyright 2013-2017 DataStax, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#++

module Cassandra
  # Sessions are used for query execution. Each session tracks its current keyspace.
  # A session should be reused as much as possible, however it is ok to create several
  # independent session for interacting with different keyspaces in the same application.
  class Session
    extend Forwardable

    # @!method keyspace
    #   Returns current keyspace
    #   @return [String] current keyspace
    def_delegators :@client, :keyspace

    # @private
    def initialize(client, default_options, futures_factory, profile_manager)
      @client  = client
      @options = default_options
      @futures = futures_factory
      @profile_manager = profile_manager
    end

    # Executes a given statement and returns a future result
    #
    # @param statement [String, Cassandra::Statements::Simple,
    #   Cassandra::Statements::Bound, Cassandra::Statements::Prepared]
    #   statement to execute
    #
    # @param options [Hash] (nil) a customizable set of options
    #
    # @option options [Symbol] :consistency consistency level for the request.
    #   Must be one of {Cassandra::CONSISTENCIES}
    # @option options [Integer] :page_size size of results page. You can page
    #   through results using {Cassandra::Result#next_page} or
    #   {Cassandra::Result#next_page_async}
    # @option options [Boolean] :trace (false) whether to enable request tracing
    # @option options [Numeric] :timeout (nil) if specified, it is a number of
    #   seconds after which to time out the request if it hasn't completed
    # @option options [Symbol] :serial_consistency (nil) this option is only
    #   relevant for conditional updates and specifies a serial consistency to
    #   be used, one of {Cassandra::SERIAL_CONSISTENCIES}
    # @option options [String] :paging_state (nil) this option is used for
    #   stateless paging, where result paging is resumed some time after the
    #   initial request.
    # @option options [Array, Hash] :arguments (nil) positional or named
    #   arguments for the statement.
    # @option options [Array, Hash] :type_hints (nil) override Util.guess_type
    #   to determine the CQL type for an argument; nil elements will fall-back
    #   to Util.guess_type.
    # @option options [Boolean] :idempotent (false) specify whether this
    #   statement can be retried safely on timeout.
    # @option options [Hash<[String, Symbol], String>] :payload (nil) custom
    #   outgoing payload to be sent with the request.
    # @option options [String, Symbol] :execution_profile (nil) name of {Cassandra::Execution::Profile}
    #   from which to obtain certain query options. Defaults to the cluster's default execution profile.
    #
    # @see Cassandra.cluster Options that can be specified on the cluster-level
    #   and their default values.
    #
    # @note Positional arguments for simple statements are only supported
    #   starting with Apache Cassandra 2.0 and above.
    #
    # @note Named arguments for simple statements are only supported
    #   starting with Apache Cassandra 2.1 and above.
    #
    # @return [Cassandra::Future<Cassandra::Result>]
    #
    # @see Cassandra::Session#execute A list of errors this future can be resolved with
    def execute_async(statement, options = nil)
      options = merge_execution_options(options)

      case statement
      when ::String
        Statements::Simple.new(statement,
                               options.arguments,
                               options.type_hints,
                               options.idempotent?).accept(@client,
                                                           options)
      when Statement
        statement.accept(@client, options)
      else
        @futures.error(::ArgumentError.new("unsupported statement #{statement.inspect}"))
      end
    rescue => e
      @futures.error(e)
    end

    # @!method execute(statement, options = nil)
    # A blocking wrapper around {Cassandra::Session#execute_async}
    #
    # @param statement [String, Cassandra::Statements::Simple,
    #   Cassandra::Statements::Bound, Cassandra::Statements::Prepared]
    #   statement to execute
    #
    # @param options [Hash] (nil) a customizable set of options. See {#execute_async} for details.
    #
    # @see Cassandra::Session#execute_async
    # @see Cassandra::Future#get
    #
    # @return [Cassandra::Result] query result
    # @raise [Cassandra::Errors::NoHostsAvailable] if all hosts fail
    # @raise [Cassandra::Errors::ExecutionError] if Cassandra fails to execute
    # @raise [Cassandra::Errors::ValidationError] if Cassandra fails to validate
    # @raise [Cassandra::Errors::TimeoutError] if request has not completed
    #   within the `:timeout` given
    def execute(statement, options = nil)
      execute_async(statement, options).get
    end

    # Prepares a given statement and returns a future prepared statement
    #
    # @param statement [String, Cassandra::Statements::Simple] a statement to
    #   prepare
    #
    # @param options [Hash] (nil) a customizable set of options
    #
    # @option options [Boolean] :trace (false) whether to enable request tracing
    # @option options [Numeric] :timeout (nil) if specified, it is a number of
    #   seconds after which to time out the request if it hasn't completed
    # @option options [Boolean] :idempotent (false) specify whether the
    #   statement being prepared can be retried safely on timeout during
    #   execution.
    # @option options [String, Symbol] :execution_profile (nil) name of {Cassandra::Execution::Profile}
    #   from which to obtain certain query options. Defaults to the cluster's default execution profile.
    #
    # @return [Cassandra::Future<Cassandra::Statements::Prepared>] future
    #   prepared statement
    def prepare_async(statement, options = nil)
      options = merge_execution_options(options)

      case statement
      when ::String
        @client.prepare(statement, options)
      when Statements::Simple
        @client.prepare(statement.cql, options)
      else
        @futures.error(::ArgumentError.new("unsupported statement #{statement.inspect}"))
      end
    rescue => e
      @futures.error(e)
    end

    # A blocking wrapper around {Cassandra::Session#prepare_async}
    #
    # @param statement [String, Cassandra::Statements::Simple] a statement to
    #   prepare
    #
    # @param options [Hash] (nil) a customizable set of options. See {#prepare_async} for details.
    #
    # @see Cassandra::Session#prepare_async
    # @see Cassandra::Future#get
    #
    # @return [Cassandra::Statements::Prepared] prepared statement
    # @raise [Cassandra::Errors::NoHostsAvailable] if none of the hosts can be reached
    # @raise [Cassandra::Errors::ExecutionError] if Cassandra returns an error response
    def prepare(statement, options = nil)
      prepare_async(statement, options).get
    end

    # Returns a logged {Statements::Batch} instance and optionally yields it to
    # a given block
    # @yieldparam batch [Statements::Batch] a logged batch
    # @return [Statements::Batch] a logged batch
    def logged_batch(&block)
      statement = Statements::Batch::Logged.new(@options)
      yield(statement) if block_given?
      statement
    end
    alias batch logged_batch

    # Returns a unlogged {Statements::Batch} instance and optionally yields it
    # to a given block
    # @yieldparam batch [Statements::Batch] an unlogged batch
    # @return [Statements::Batch] an unlogged batch
    def unlogged_batch
      statement = Statements::Batch::Unlogged.new(@options)
      yield(statement) if block_given?
      statement
    end

    # Returns a counter {Statements::Batch} instance and optionally yields it
    # to a given block
    # @yieldparam batch [Statements::Batch] a counter batch
    # @return [Statements::Batch] a counter batch
    def counter_batch
      statement = Statements::Batch::Counter.new(@options)
      yield(statement) if block_given?
      statement
    end

    # Asynchronously closes current session
    #
    # @return [Cassandra::Future<Cassandra::Session>] a future that resolves to
    #   self once closed
    def close_async
      promise = @futures.promise

      @client.close.on_complete do |f|
        if f.resolved?
          promise.fulfill(self)
        else
          f.on_failure {|e| promise.break(e)}
        end
      end

      promise.future
    end

    # Synchronously closes current session
    #
    # @return [self] this session
    #
    # @see Cassandra::Session#close_async
    def close
      close_async.get
    end

    # @private
    def inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} " \
      "@keyspace=#{keyspace.inspect}, " \
      "@options=#{@options.inspect}>"
    end

    private

    # @private
    def merge_execution_options(options)
      if options
        Util.assert_instance_of(::Hash, options, "options must be a Hash, #{options.inspect} given")
        # Yell if the caller gave us a bad profile name.
        execution_profile = nil
        if options.key?(:execution_profile)
          execution_profile = @profile_manager.profiles[options[:execution_profile]]
          raise ::ArgumentError.new("Unknown execution profile #{options[:execution_profile]}") unless execution_profile
        end

        # This looks a little hokey, so let's explain: Execution::Options.override takes a
        # varargs-style array of things to merge into the base options object (to produce
        # a new Options object, not mutate the base). If an execution profile was specified,
        # we want its attributes to override the base options. In addition, if individual options
        # were specified, we want *those* to take precedence over the execution profile attributes.
        # So we override in this order.
        @options.override(execution_profile, options)
      else
        @options
      end
    end
  end
end
