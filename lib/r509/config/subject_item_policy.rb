require 'yaml'
require 'openssl'
require 'r509/exceptions'
require 'r509/io_helpers'
require 'r509/subject'
require 'r509/private_key'
require 'r509/engine'
require 'fileutils'
require 'pathname'

module R509
  # Module to contain all configuration related classes (e.g. CAConfig, CertProfile, SubjectItemPolicy)
  module Config
    # The Subject Item Policy allows you to define what subject fields are allowed in a
    # certificate. Required means that field *must* be supplied, optional means it will
    # be encoded if provided, and match means the field must be present and must match
    # the value specified.
    #
    # Using R509::OIDMapper you can create new shortnames that will be usable inside this class.
    class SubjectItemPolicy
      # @return [Array]
      attr_reader :required, :optional, :match, :match_values

      # @param [Hash] hash of required/optional/matching subject items. These must be in OpenSSL shortname format.
      # @example sample hash
      #  {"CN" => { :policy => "required" },
      #  "O" => { :policy => "required" },
      #  "OU" => { :policy => "optional" },
      #  "ST" => { :policy => "required" },
      #  "C" => { :policy => "required" },
      #  "L" => { :policy => "match", :value => "Chicago" },
      #  "emailAddress" => { :policy => "optional" }
      def initialize(hash = {})
        unless hash.is_a?(Hash)
          raise ArgumentError, "Must supply a hash in form 'shortname'=>hash_with_policy_info"
        end
        @required = []
        @optional = []
        @match_values = {}
        @match = []
        return if hash.empty?
        hash.each_pair do |key, value|
          unless value.is_a?(Hash)
            raise ArgumentError, "Each value must be a hash with a :policy key"
          end
          case value[:policy]
          when 'required' then @required.push(key)
          when 'optional' then @optional.push(key)
          when 'match' then
            @match_values[key] = value[:value]
            @match.push(key)
          else
            raise ArgumentError, "Unknown subject item policy value. Allowed values are required, optional, or match"
          end
        end
      end

      # @param [R509::Subject] subject
      # @return [R509::Subject] validated version of the subject or error
      def validate_subject(subject)
        # check if match components are present and match
        validate_match(subject)
        validate_required_match(subject)

        # the validated subject contains only those subject components that are either
        # required, optional, or match
        R509::Subject.new(subject.to_a.select do |item|
          @required.include?(item[0]) || @optional.include?(item[0]) || @match.include?(item[0])
        end)
      end

      # @return [Hash]
      def to_h
        hash = {}
        @required.each { |r| hash[r] = { :policy => "required" } }
        @optional.each { |o| hash[o] = { :policy => "optional" } }
        @match.each { |m| hash[m] = { :policy => "match", :value => @match_values[m] } }
        hash
      end

      # @return [YAML]
      def to_yaml
        self.to_h.to_yaml
      end

      private

      # validates that the provided subject has the expected values for the
      # match policy
      def validate_match(subject)
        subject.to_a.each do |item|
          if @match.include?(item[0])
            if @match_values[item[0]] != item[1]
              raise R509::R509Error, "This profile requires that #{item[0]} have value: #{@match_values[item[0]]}"
            end
          end
        end unless @match.empty?
      end

      # validates that all the subject elements that are required or match in the
      # subject item policy are present in the supplied subject
      def validate_required_match(subject)
        # convert the subject components into an array of component names that match
        # those that are on the required list
        supplied = subject.to_a.each do |item|
          @required.include?(item[0]) || @match.include?(item[0])
        end
        supplied = supplied.map { |item| item[0] }
        # so we can make sure they gave us everything that's required
        diff = @required + @match - supplied
        raise R509::R509Error, "This profile requires you supply " + (@required + @match).join(", ") unless diff.empty?
      end
    end
  end
end
