class OTPAmbassador
  def initialize(trip, trip_types, http_request_bundler, services)
    @trip = trip
    @trip_types = trip_types
    @http_request_bundler = http_request_bundler
    @services = services
    @otp_service = OTPService.new
  end

  def get_itineraries(trip_type)
    from = [@trip.origin.lat, @trip.origin.lng]
    to = [@trip.destination.lat, @trip.destination.lng]
    response = @otp_service.plan(from, to, @trip.trip_time, @trip.arrive_by)
    response["data"]["plan"]["itineraries"]
  end

  def get_duration(trip_type)
    itineraries = get_itineraries(trip_type)
    itineraries.first["duration"] if itineraries.present?
  end
end