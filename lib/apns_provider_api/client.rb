require 'http/2'
require 'uri'
require 'socket'
require 'openssl'

module ApnsProviderApi

  APPLE_DEVELOPMENT_GATEWAY_URI = "https://api.development.push.apple.com:443"
  APPLE_PRODUCTION_GATEWAY_URI = "https://api.push.apple.com:443"

  class Client
    attr_accessor :gateway_uri, :feedback_uri, :certificate, :passphrase, :timeout, :split_size

    class << self
      def development
        client = self.new
        client.gateway_uri = APPLE_DEVELOPMENT_GATEWAY_URI
        client
      end

      def production
        client = self.new
        client.gateway_uri = APPLE_PRODUCTION_GATEWAY_URI
        client
      end

      def mock
        client = self.new
        client.gateway_uri = "apn://127.0.0.1:2195"
        client
      end
    end

    def initialize
      @gateway_uri = ENV['APN_GATEWAY_URI']
      @certificate = File.read(ENV['APN_CERTIFICATE']) if ENV['APN_CERTIFICATE']
      @passphrase = ENV['APN_CERTIFICATE_PASSPHRASE']
      @pid = Process.pid
      @failed_notifications, @failed_streams, @notifications = [], [], []
    end

    def enqueue(notifications)
     @split_size ||= 500
      notifications.each_slice(@split_size) do |group|
        push(group)
      end
      @failed_notifications
    end

    def push(notifications)
      return if notifications.empty?

      @notifications = notifications.flatten
      @counter = 0

      head = {
        ':scheme' => 'https',
        ':method' => 'POST'
        # ':apns-expiration' => 0 #do not store for sending late
        #'content-length' => notification.message.size
      }

      Connection.open(@gateway_uri, @certificate, @passphrase) do |connection|
        ssl_sock = connection.ssl
        # events(connection.http2client, ssl_sock)

        @notifications.each_with_index do |notification, index|
          connection.open?
          head[':path'] = "/3/device/#{notification.token}"
          head[':apns-id'] = notification.uuid

          stream = connection.new_stream

          # because apple is not returning the uuid when push fails,
          # i'm replacing uuid to stream id
          notification.uuid = stream.id

          stream.on(:headers) do |h|
           # puts "headers: #{h} - stream_id: #{stream.id}"
            read_headers(Hash[*h.flatten], stream)
          end
          stream.on(:data) do |d|
            # puts "data: #{d}"
            # puts "#{JSON.parse(d)} - #{stream.id.to_s}"
            read_body(JSON.parse(d), stream)
          end
          stream.headers(head, end_stream: false)
          stream.data(notification.payload.to_json)
        end

        # keep_reading = true

        while !ssl_sock.closed? && !ssl_sock.eof?
          data = ssl_sock.read_nonblock(1024)
          # puts "Received bytes: #{data.unpack("H*").first}"
          begin
            connection.http2client << data
            return if @counter == @notifications.size
          rescue => e
            puts "Exception: #{e}, #{e.message} - closing socket."
            ssl_sock.close
          end
        end
      end
    end

    def read_headers(headers, stream)
      # puts headers[':status']
      if headers[':status'].to_i == 200
        # when notification succeeds, we wont receive body
        increase_counter
      else
        @failed_streams << stream
      end
    end

    def read_body(response, stream)
      increase_counter
      return unless @failed_streams.include?(stream)
      notification = @notifications.select{|n| n.uuid == stream.id}[0]
      notification.error_message = response['reason']
      @failed_notifications << notification
    end

    def increase_counter
      @counter += 1
    end
  end
end