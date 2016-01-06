require 'json'
require 'securerandom'

module ApnsProviderApi
  class Notification
    class APNSError < RuntimeError
      # See: https://developer.apple.com/library/ios/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/APNsProviderAPI.html
      CODES = {
        200 => "Success",
        400 => "Bad request",
        403 => "There was an error with the certificate",
        405 => "The request used a bad :method value. Only POST requests are supported",
        410 => "The device token is no longer active for the topic",
        413 => "The notification payload was too large",
        429 => "The server received too many requests for the same device token",
        500 => "Internal server error",
        503 => "The server is shutting down and unavailable"
      }

      attr_reader :code

      def initialize(code)
        raise ArgumentError unless CODES.include?(code)
        super(CODES[code])
        @code = code
      end
    end

    # MAXIMUM_PAYLOAD_SIZE = 4096 already accepted by provider API but not for iOS apps
    MAXIMUM_PAYLOAD_SIZE = 2048

    attr_accessor :token, :alert, :badge, :sound, :category, :content_available, :custom_data, :id, :expiry, :priority, :uuid, :error_message
    attr_reader :sent_at
    # attr_writer :apns_error_code

    alias :device :token
    alias :device= :token=

    def initialize(options = {})
      @token = options.delete(:token) || options.delete(:device)
      raise 'invalid token' if @token && @token.empty?
      @badge = options.delete(:badge)
      @sound = options.delete(:sound)
      @category = options.delete(:category)
      @expiry = options.delete(:expiry)
      @id = options.delete(:id)
      @priority = options.delete(:priority)
      @content_available = options.delete(:content_available)
      dottize = options.delete(:dottize)
      @custom_data = options
      alert = options.delete(:alert)
      available_bytes = MAXIMUM_PAYLOAD_SIZE - payload.to_s.bytesize
      @alert = trim_alert(alert, available_bytes, dottize)
      generate_uuid(options.delete(:uuid))
    end

    def payload
      json = {}.merge(@custom_data || {}).inject({}){|h,(k,v)| h[k.to_s] = v; h}

      json['aps'] ||= {}
      json['aps']['alert'] = @alert if @alert
      json['aps']['badge'] = @badge.to_i rescue 0 if @badge
      json['aps']['sound'] = @sound if @sound
      json['aps']['category'] = @category if @category
      json['aps']['content-available'] = 1 if @content_available

      json
    end

    def mark_as_sent!
      @sent_at = Time.now
    end

    def mark_as_unsent!
      @sent_at = nil
    end

    def sent?
      !!@sent_at
    end

    def trim_alert(alert, available_bytes, dottize)
      if alert.size > available_bytes
        raise "the notification payload was too large \nTip: use dottize option to auto trim the notification alert" unless dottize
        chars_to_delete = alert.size - available_bytes
        alert =  dottize_no_broken_words(alert, alert.size - chars_to_delete)
      end
      alert
    end

    # def error
    #   APNSError.new(@apns_error_code) if @apns_error_code and @apns_error_code.nonzero?
    # end

    private

    def generate_uuid(uuid=nil)
      uuid = SecureRandom.uuid unless uuid
      @uuid = uuid
    end

    def dottize_no_broken_words(string, limit=3)
      size = string.size
      size > limit ? "#{string[0,string[0,limit-3].rindex(" ") || limit-3]}..." : string
    end

  end
end
