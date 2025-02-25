module Admin
  class UsersReportCSVWriter < CSVWriter
    columns :email, :first_name, :last_name, 
            :trips_planned, :created_at
    associations :trips, :preferred_locale
    
    def trips_planned
      @record.trips.joins(:ecolane_booking_snapshot).distinct.count
    end    

  end
end