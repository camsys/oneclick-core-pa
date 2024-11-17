module OTP
  class OTPService
    def plan(from, to, trip_datetime, arrive_by = true, options = {})
      url = "https://hopelink-otp.ibi-transit.com/otp/routers/default/index/graphql"
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
              legs {
                mode
                from {
                  name
                  lat
                  lon
                }
                to {
                  name
                  lat
                  lon
                }
                distance
              }
            }
          }
        }
      GRAPHQL

      variables = {
        fromLat: from[0].to_f,
        fromLon: from[1].to_f,
        toLat: to[0].to_f,
        toLon: to[1].to_f,
        date: trip_datetime.strftime("%Y-%m-%d"),
        time: trip_datetime.strftime("%H:%M")
      }

      headers = {
        'Content-Type' => 'application/json',
        'x-user-email' => '1-click@camsys.com',
        'x-user-token' => 'sRRTZ3BV3tmms1o4QNk2'
      }

      body = { query: query, variables: variables }.to_json

      response = make_graphql_request(url, body, headers)
      JSON.parse(response.body)
    end

    def make_graphql_request(url, body, headers)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      request = Net::HTTP::Post.new(uri.request_uri, headers)
      request.body = body
      http.request(request)
    end
  end
end