module Types
  class QueryType < Types::BaseObject
    field :trip, Types::TripType, null: false do
      argument :id, ID, required: true
    end

    def trip(id:)
      Trip.find(id)
    end

    field :plan_trip, Types::TripPlanType, null: false do
      argument :origin, Types::CoordinatesInput, required: true
      argument :destination, Types::CoordinatesInput, required: true
      argument :time, String, required: true
      argument :arrive_by, Boolean, required: true
      argument :modes, [String], required: true
    end

    def plan_trip(origin:, destination:, time:, arrive_by:, modes:)
      trip = Trip.new(
        origin: Location.new(lat: origin[:lat], lng: origin[:lon]),
        destination: Location.new(lat: destination[:lat], lng: destination[:lon]),
        trip_time: Time.parse(time),
        arrive_by: arrive_by
      )

      otp_ambassador = OTPAmbassador.new(trip)
      otp_ambassador.get_itineraries(modes.first.to_sym)
    end
  end
end
