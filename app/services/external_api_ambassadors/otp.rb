# require 'json'
# require 'net/http'
# require 'eventmachine' # For multi_plan
# require 'em-http' # For multi_plan

# Namespaced module for containing helper classes for interacting with OTP via rails.
# Doesn't know about 1-Click models, controllers, etc.
module OTP

  class OTPService
    attr_accessor :base_url
    attr_accessor :version

    def initialize(base_url="", version="v1")
      @base_url = base_url
      @version = version
      Rails.logger.info "OTPService initialized with base_url: #{@base_url} and version: #{@version}"
    end

    # Makes multiple OTP requests in parallel, and returns once they're all done.
    # Send it a list or array of request hashes.

    def multi_plan(*requests)
      requests = requests.flatten.uniq { |req| req[:label] } # Discard duplicate labels
      responses = nil
      EM.run do
        multi = EM::MultiRequest.new
        requests.each_with_index do |request, i|
          url = plan_url(request) # GraphQL endpoint
          body = build_url(request[:from], request[:to], request[:trip_time], request[:arrive_by], request[:options] || {})

          multi.add(
            (request[:label] || "req#{i}".to_sym),
            EM::HttpRequest.new(url, connect_timeout: 60, inactivity_timeout: 60, tls: { verify_peer: true })
                            .post(
                              head: { 'Content-Type' => 'application/json' },
                              body: body
                            )
          )
        end

        multi.callback do
          EM.stop
          responses = multi.responses
        end
      end
      responses
    end

    # Constructs an OTP request url
    def plan_url(request)
      "#{@base_url}/index/graphql"
    end

    ###
    # from and to should be [lat,lng] arrays;
    # trip_datetime should be a DateTime object;
    # arrive_by should be a boolean
    # Accepts a hash of additional options, none of which are required to make the plan call run
    def plan(from, to, trip_datetime, arrive_by = true, options = {})
      url = "https://hopelink-otp.ibi-transit.com/otp/routers/default/index/graphql"
    
      # Define the GraphQL query
      query = <<-GRAPHQL
        query($fromLat: Float!, $fromLon: Float!, $toLat: Float!, $toLon: Float!, $date: String!, $time: String!) {
          plan(
            from: { lat: $fromLat, lon: $fromLon }
            to: { lat: $toLat, lon: $toLon }
            date: $date
            time: $time
            transportModes: [{ mode: TRANSIT }, { mode: WALK }]
          ) {
            itineraries {
              startTime
              endTime
              duration
              walkDistance
              fares {
                type
                cents
                currency
                components {
                  fareId
                  currency
                  cents
                  routes {
                    gtfsId
                    shortName
                  }
                }
              }
              legs {
                mode
                distance
                from {
                  name
                  lat
                  lon
                  departureTime
                }
                to {
                  name
                  lat
                  lon
                  arrivalTime
                }
                fareProducts {
                  id
                  product {
                    name
                    ... on DefaultFareProduct {
                      price {
                        amount
                        currency {
                          code
                          digits
                        }
                      }
                    }
                    riderCategory {
                      name
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    
      # Define variables for the GraphQL query
      variables = {
        fromLat: from[0].to_f,
        fromLon: from[1].to_f,
        toLat: to[0].to_f,
        toLon: to[1].to_f,
        date: trip_datetime.strftime("%Y-%m-%d"),
        time: trip_datetime.strftime("%H:%M")
      }
    
      # Headers for the GraphQL request
      headers = {
        'Content-Type' => 'application/json',
        'x-user-email' => '1-click@camsys.com',
        'x-user-token' => 'sRRTZ3BV3tmms1o4QNk2'
      }
    
      # Body for the GraphQL request
      body = { query: query, variables: variables }.to_json
    
      # Log the request details
      Rails.logger.info("Sending GraphQL request with URL: #{url}")
      Rails.logger.info("Request body: #{body}")
    
      # Make the GraphQL request and assign the response to `resp`
      resp = make_graphql_request(url, body, headers)
    
      # Log the raw response
      Rails.logger.info("GraphQL response: #{resp.body}")
    
      # Return `resp` directly, as other parts of your code expect it
      resp
    rescue => e
      # Log and return an error message in `resp` format
      Rails.logger.error("GraphQL request failed with error: #{e}")
      OpenStruct.new(body: { 'id' => 500, 'msg' => e.to_s }.to_json)
    end
   
    # Helper method to make the GraphQL request
    def make_graphql_request(url, body, headers)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')

      request = Net::HTTP::Post.new(uri.request_uri, headers)
      request.body = body

      http.request(request)
    end
    
    def parse_itinerary(itinerary)
      Rails.logger.info("Parsing itinerary: #{itinerary}")
      {
        startTime: Time.at(itinerary["startTime"] / 1000),
        endTime: Time.at(itinerary["endTime"] / 1000),
        legs: itinerary["legs"].map do |leg|
          {
            mode: leg["mode"],
            from: { name: leg["from"]["name"], lat: leg["from"]["lat"], lon: leg["from"]["lon"] },
            to: { name: leg["to"]["name"], lat: leg["to"]["lat"], lon: leg["to"]["lon"] },
            points: leg["legGeometry"]["points"]
          }
        end
      }
    end

    def build_url(from, to, trip_datetime, arrive_by = true, options = {})
    query = <<-GRAPHQL
      query($fromLat: Float!, $fromLon: Float!, $toLat: Float!, $toLon: Float!, $date: String!, $time: String!, $mode: [TransportModeInput!], $wheelchair: Boolean, $walkSpeed: Float, $maxWalkDistance: Float) {
        plan(
          from: { lat: $fromLat, lon: $fromLon }
          to: { lat: $toLat, lon: $toLon }
          date: $date
          time: $time
          arriveBy: #{arrive_by}
          transportModes: $mode
          wheelchair: $wheelchair
          walkSpeed: $walkSpeed
          maxWalkDistance: $maxWalkDistance
        ) {
          itineraries {
            startTime
            endTime
            duration
            walkDistance
            fares {
              type
              cents
              currency
            }
            legs {
              mode
              distance
              from {
                name
                lat
                lon
                departureTime
              }
              to {
                name
                lat
                lon
                arrivalTime
              }
            }
          }
        }
    GRAPHQL

    # Default and optional settings based on options provided
    mode = options[:mode] || ["TRANSIT", "WALK"]
    wheelchair = options[:wheelchair] || false
    walk_speed = options[:walk_speed] || 1.34 # Convert 3 mph to m/s as per GraphQL API needs
    max_walk_distance = (options[:max_walk_distance] || 2) * 1609.34 # Convert miles to meters

    # Define variables for the GraphQL query
    variables = {
      fromLat: from[0].to_f,
      fromLon: from[1].to_f,
      toLat: to[0].to_f,
      toLon: to[1].to_f,
      date: trip_datetime.strftime("%Y-%m-%d"),
      time: trip_datetime.strftime("%H:%M"),
      mode: mode.map { |m| { mode: m } },
      wheelchair: wheelchair,
      walkSpeed: walk_speed,
      maxWalkDistance: max_walk_distance
    }

    # Log the generated query and variables for debugging
    Rails.logger.info("Generated GraphQL query: #{query}")
    Rails.logger.info("With variables: #{variables}")

    # Return the JSON body that includes the query and variables
      { query: query, variables: variables }.to_json
    end


    def last_built
      url = @base_url
      resp = Net::HTTP.get_response(URI.parse(url))
      data = JSON.parse(resp.body)
      time = data['buildTime']/1000
      return Time.at(time)
    end

    def get_stops
      stops_path = '/index/stops'
      url = @base_url + stops_path
      resp = Net::HTTP.get_response(URI.parse(url))
      return JSON.parse(resp.body)
    end

    def get_routes
      routes_path = '/index/routes'
      url = @base_url + routes_path
      resp = Net::HTTP.get_response(URI.parse(url))
      return JSON.parse(resp.body)
    end

    def get_first_feed_id
      path = '/index/feeds'
      url = @base_url + path
      resp = Net::HTTP.get_response(URI.parse(url))
      return JSON.parse(resp.body).first
    end

    def get_stoptimes trip_id, agency_id=1
      path = '/index/trips/' + agency_id.to_s + ':' + trip_id.to_s + '/stoptimes'
      url = @base_url + path
      resp = Net::HTTP.get_response(URI.parse(url))
      return JSON.parse(resp.body)
    end

    # Dead code? Drew Teter - 4/7/2023
    # def get_otp_mode trip_type
    #   hash = {'transit': 'TRANSIT,WALK',
    #   'bicycle_transit': 'TRANSIT,BICYCLE',
    #   'park_transit': 'CAR_PARK,WALK,TRANSIT',
    #   'car_transit': 'CAR,WALK,TRANSIT',
    #   'bike_park_transit': 'BICYCLE_PARK,WALK,TRANSIT',
    #   'paratransit': 'TRANSIT,WALK,FLEX_ACCESS,FLEX_EGRESS,FLEX_DIRECT',
    #   'rail': 'TRAM,SUBWAY,RAIL,WALK',
    #   'bus': 'BUS,WALK',
    #   'walk': 'WALK',
    #   'car': 'CAR',
    #   'bicycle': 'BICYCLE'}
    #   hash[trip_type.to_sym]
    # end

    # Wraps a response body in an OTPResponse object for easy inspection and manipulation
    def unpack(response)
      return OTPResponse.new(response)
    end

  end

  # Wrapper class for OTP Responses
  class OTPResponse
    attr_accessor :response, :itineraries

    # Pass a response body hash (e.g. parsed JSON) to initialize
    def initialize(response)
      response = JSON.parse(response) if response.is_a?(String)
      @response = response.with_indifferent_access
      @itineraries = extract_itineraries
    end

    # Allows you to access the response with [key] method
    # first converts key to lowerCamelCase
    def [](key)
      @response[key.to_s.camelcase(:lower)]
    end

    # Returns the array of itineraries
    def extract_itineraries
      return [] unless @response && @response[:plan] && @response[:plan][:itineraries]
      @response[:plan][:itineraries].map {|i| OTPItinerary.new(i)}
    end

  end


  # Wrapper class for OTP Itineraries
  class OTPItinerary
    attr_accessor :itinerary

    # Pass an OTP itinerary hash (e.g. parsed JSON) to initialize
    def initialize(itinerary)
      itinerary = JSON.parse(itinerary) if itinerary.is_a?(String)
      @itinerary = itinerary.with_indifferent_access
    end

    # Allows you to access the itinerary with [key] method
    # first converts key to lowerCamelCase
    def [](key)
      @itinerary[key.to_s.camelcase(:lower)]
    end

    # Extracts the fare value in dollars
    def fare_in_dollars
      @itinerary['fare'] &&
      @itinerary['fare']['fare'] &&
      @itinerary['fare']['fare']['regular'] &&
      @itinerary['fare']['fare']['regular']['cents'].to_f/100.0
    end

    # Getter method for itinerary's legs
    def legs
      OTPLegs.new(@itinerary['legs'] || [])
    end

    # Setter method for itinerary's legs
    def legs=(new_legs)
      @itinerary['legs'] = new_legs.try(:to_a)
    end
    
  end


  # Wrapper class for OTP Legs array, providing helper methods
  class OTPLegs
    attr_reader :legs
    
    # Pass an OTP legs array (e.g. parsed or un-parsed JSON) to initialize
    def initialize(legs)
      
      # Parse the legs array if it's a JSON string
      legs = JSON.parse(legs) if legs.is_a?(String)
      
      # Make the legs array an array of hashes with indifferent access
      @legs = legs.map { |l| l.try(:with_indifferent_access) }.compact
    end
    
    # Return legs array on to_a
    def to_a
      @legs
    end
    
    # Pass to_s method along to legs array
    def to_s
      @legs.to_s
    end
    
    # Pass map method along to legs array
    def map &block
      @legs.map &block
    end
    
    # Pass each method along to legs array
    def each &block
      @legs.each &block
    end
    
    # Returns first instance of an attribute from the legs
    def detect &block
      @legs.detect &block
    end
    
    # Returns an array of all non-nil instances of the given value in the legs
    def pluck(attribute)
      @legs.pluck(attribute).compact
    end
    
    # Sums up an attribute across all legs, ignoring nil and non-numeric values
    def sum_by(attribute)
      @legs.pluck(attribute).select{|i| i.is_a?(Numeric)}.reduce(&:+)
    end
  
  end

end
