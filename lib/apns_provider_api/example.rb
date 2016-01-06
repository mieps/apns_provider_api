require_relative 'client'
require_relative 'connection'
require_relative 'notification'

APN = ApnsProviderApi::Client.production
TOKEN_ARRAY = ["123", "321"]
APN.certificate = File.read("cert.pem")
APN.passphrase = File.read("pass.txt")


notification_array = []

TOKEN_ARRAY.each do |token|
  notification = ApnsProviderApi::Notification.new(badge: 1,
                                                   device: token,
                                                   alert: "TEST #{token}",
                                                   sound: "sosumi.aiff")
  notification_array << notification
end


failed_notifications = APN.enqueue(notification_array)
puts failed_notifications