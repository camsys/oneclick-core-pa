class TripPlanner
  include OTP

  # Constant list of trip types that can be planned
  TRIP_TYPES = Trip::TRIP_TYPES

  attr_reader :options, :router, :errors, :trip_types, :available_services,
              :http_request_bundler, :filters, :only_filters, :except_filters

  attr_accessor :trip

  def initialize(trip, options = {})
    @trip = trip
    @options = options
    @trip_types = (options[:trip_types] || TRIP_TYPES) & TRIP_TYPES
    @purpose = Purpose.find_by(id: @options[:purpose_id])

    @errors = []
    @available_services = options[:available_services] || Service.published
    @http_request_bundler = options[:http_request_bundler] || HTTPRequestBundler.new

    # Filters for service availability
    @only_filters = (options[:only_filters] || Service::AVAILABILITY_FILTERS) & Service::AVAILABILITY_FILTERS
    @except_filters = options[:except_filters] || []
    @filters = @only_filters - @except_filters

    prepare_ambassadors
  end

  def plan
    set_available_services
    build_all_itineraries
    filter_itineraries
    @trip.save
  end

  private

  def prepare_ambassadors
    @router = OTPAmbassador.new(@trip, @trip_types, @http_request_bundler, @available_services[:transit].or(@available_services[:paratransit]))
  end

  def set_available_services
    @available_services = @available_services.by_trip_type(*@trip_types)
    @available_services = @available_services.available_for(@trip, only_by: (@filters - [:purpose, :eligibility, :accommodation]))
    @available_services = @available_services.available_for(@trip, only_by: (@filters & [:purpose, :eligibility]))
    @available_services = available_services_hash(@available_services)
  end

  def available_services_hash(services)
    Service::SERVICE_TYPES.map do |t|
      [t.underscore.to_sym, services.where(type: t)]
    end.to_h.merge({ all: services })
  end

  def build_all_itineraries
    trip_itineraries = @trip_types.flat_map { |t| build_itineraries(t) }
    @trip.itineraries = trip_itineraries.compact
  end

  def build_itineraries(trip_type)
    send("build_#{trip_type}_itineraries")
  end

  def build_transit_itineraries
    build_fixed_itineraries(:transit)
  end

  def build_walk_itineraries
    build_fixed_itineraries(:walk)
  end

  def build_car_itineraries
    build_fixed_itineraries(:car)
  end

  def build_paratransit_itineraries
    return [] unless @available_services[:paratransit].present?

    itineraries = @available_services[:paratransit].map do |svc|
      itinerary = Itinerary.new(
        service: svc,
        trip_type: :paratransit,
        cost: svc.fare_for(@trip, router: @router),
        transit_time: @router.get_duration(:paratransit)
      )
      itinerary
    end

    itineraries + @router.get_itineraries(:paratransit)
  end

  def build_fixed_itineraries(trip_type)
    @router.get_itineraries(trip_type).map { |i| Itinerary.new(i) }
  end

  def filter_itineraries
    max_walk_distance = Config.max_walk_distance
    @trip.itineraries.reject! do |itin|
      itin.walk_distance > max_walk_distance if itin.trip_type == "walk"
    end
  end
end