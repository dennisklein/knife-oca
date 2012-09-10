#
# Modified by:: Dennis Klein (<d.klein@gsi.de>)
#
# Author:: Seth Chisamore (<schisamo@opscode.com>)
# Copyright:: Copyright (c) 2011 Opscode, Inc.
# License:: Apache License, Version 2.0
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
#

require 'chef/knife'
require 'resolv'

class Chef
  class Knife
    module OCABase

      # :nodoc:
      # Would prefer to do this in a rational way, but can't be done b/c of
      # Mixlib::CLI's design :(
      def self.included(includer)
        includer.class_eval do

          deps do
            require 'fog'
            require 'readline'
            require 'chef/json_compat'
          end

          option :oca_one_auth,
            :short => "-K ONE_AUTH",
            :long => "--oca-one-auth ONE_AUTH",
            :description => "Your OCA OpenNebula username:password credentials",
            :proc => Proc.new { |key| Chef::Config[:knife][:oca_one_auth] = key }
          
          option :oca_xml_rpc_endpoint,
            :short => "-C ENDPOINT",
            :long => "--oca-xml-rpc-endpoint ENDPOINT",
            :description => "Your OCA OpenNebula XML-RPC endpoint, e.g. http://host:port/RPC2",
            :proc => Proc.new { |key| Chef::Config[:knife][:oca_xml_rpc_endpoint] = key }
        end
      end

      def connection
        @connection ||= begin
          connection = Fog::Compute.new(
            :provider => 'OCA',
            :oca_one_auth => Chef::Config[:knife][:oca_one_auth],
            :aws_xml_rpc_endpoint => Chef::Config[:knife][:oca_xml_rpc_endpoint],
          )
        end
      end

      def locate_config_value(key)
        key = key.to_sym
        config[key] || Chef::Config[:knife][key]
      end

      def msg_pair(label, value, color=:cyan)
        if value && !value.to_s.empty?
          puts "#{ui.color(label, color)}: #{value}"
        end
      end

      def validate!(keys=[:oca_one_auth, :oca_xml_rpc_endpoint])
        errors = []

        keys.each do |k|
          pretty_key = k.to_s.gsub(/_/, ' ').gsub(/\w+/){ |w| (w =~ /(ssh)|(oca)/i) ? w.upcase : w.capitalize }
          if Chef::Config[:knife][k].nil?
            errors << "You did not provide a valid '#{pretty_key}' value."
          end
        end

        if errors.each{|e| ui.error(e)}.any?
          exit 1
        end
      end

      def dns_reverse_lookup(ip)
        Resolv::DNS.new.getname(ip.to_s).to_s
      end

    end
  end
end
