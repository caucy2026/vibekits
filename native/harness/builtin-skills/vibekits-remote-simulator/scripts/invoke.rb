#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'uri'

abort('usage: invoke.rb TOOL_ID [ARGUMENTS_JSON]') unless (1..2).cover?(ARGV.length)

tool_id = ARGV[0]
begin
  arguments = ARGV[1] ? JSON.parse(ARGV[1]) : {}
rescue JSON::ParserError => e
  abort("invalid arguments JSON: #{e.message}")
end
abort('arguments must be a JSON object') unless arguments.is_a?(Hash)

connection_path = File.join(
  Dir.home,
  'Library',
  'Application Support',
  'com.caucy.vibekits',
  'Vibekits',
  'mcp',
  'tool-bridge.json'
)

begin
  connection = JSON.parse(File.read(connection_path))
rescue Errno::ENOENT
  abort('VibeKits tool bridge is not running or its connection file is missing')
rescue JSON::ParserError => e
  abort("VibeKits tool bridge connection file is invalid: #{e.message}")
end

endpoint = connection.fetch('endpoint')
token = connection.fetch('token')
abort('VibeKits tool bridge token is empty') if token.to_s.empty?

uri = URI.join(endpoint.end_with?('/') ? endpoint : "#{endpoint}/", 'invoke')
allowed_hosts = ['127.0.0.1', '::1', 'localhost']
abort('refusing a non-loopback tool bridge endpoint') unless uri.scheme == 'http' && allowed_hosts.include?(uri.host)

request = Net::HTTP::Post.new(uri)
request['Accept'] = 'application/json'
request['Content-Type'] = 'application/json'
request['Authorization'] = "Bearer #{token}"
request.body = JSON.generate({ 'toolId' => tool_id, 'arguments' => arguments })

http = Net::HTTP.new(uri.host, uri.port)
http.open_timeout = 5
http.read_timeout = 1_200
http.write_timeout = 1_200 if http.respond_to?(:write_timeout=)

begin
  response = http.request(request)
rescue StandardError => e
  abort("VibeKits tool bridge request failed: #{e.class}: #{e.message}")
end

puts response.body
exit(response.is_a?(Net::HTTPSuccess) ? 0 : 3)
