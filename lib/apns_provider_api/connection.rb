require 'http/2'
require 'forwardable'

module ApnsProviderApi
  class Connection
    extend Forwardable
    def_delegators :@ssl, :read, :write
    def_delegators :@uri, :scheme, :host, :port
    # def_delegators :@stream, :headers, :data

    attr_reader :ssl, :socket, :certificate, :passphrase, :http2client

    class << self
      def open(uri, certificate, passphrase)
        return unless block_given?

        connection = new(uri, certificate, passphrase)
        connection.open

        yield connection

        connection.close
      end
    end

    def initialize(uri, certificate, passphrase)
      @uri = URI(uri)
      @certificate = certificate
      @passphrase = passphrase
      @http2client = HTTP2::Client.new
      events
      @http2client
    end

    def open
      return false if open?

      @socket = TCPSocket.new(@uri.host, @uri.port)
      context = OpenSSL::SSL::SSLContext.new
      context.key = OpenSSL::PKey::RSA.new(@certificate, @passphrase)
      context.cert = OpenSSL::X509::Certificate.new(certificate)

      @ssl = OpenSSL::SSL::SSLSocket.new(@socket, context)
      @ssl.sync_close = true
      @ssl.hostname = @uri.hostname
      @ssl.connect
    end

    def open?
      not (@ssl and @socket).nil?
    end

    def close
      return false if closed?
      @socket.close
      @socket = nil

      @ssl.close
      @ssl = nil

    end

    def closed?
      not open?
    end

    def new_stream
      @http2client.new_stream
    end

    def events
      @http2client.on(:frame) do |bytes|
        # puts "Sending bytes: #{bytes.unpack("H*").first}"
        ssl.print bytes
        ssl.flush
      end
    end
  end
end