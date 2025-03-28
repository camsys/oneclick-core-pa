require 'rails_helper'

RSpec.describe "TravelPattern time filtering", type: :model do
  let!(:agency) { create(:transportation_agency) }
  let!(:zone)   { create(:od_zone, agency: agency) }
  let(:monday) { Date.parse("2025-04-07") }

  let!(:multi_schedule) { create(:service_schedule, agency: agency) }
  let!(:tp_multi) do
    tp = create(:travel_pattern, agency: agency, origin_zone: zone, destination_zone: zone)
    tp.travel_pattern_service_schedules.create!(service_schedule: multi_schedule, priority: 1)
    tp
  end

  before do
    create(:service_sub_schedule, service_schedule: multi_schedule, day: 1,
           start_time: 9.hours.to_i, end_time: 15.hours.to_i)
    create(:service_sub_schedule, service_schedule: multi_schedule, day: 1,
           start_time: 17.hours.to_i, end_time: 21.hours.to_i)
  end

  let!(:evening_schedule) { create(:service_schedule, agency: agency) }
  let!(:tp_evening_only) do
    tp = create(:travel_pattern, agency: agency, origin_zone: zone, destination_zone: zone)
    tp.travel_pattern_service_schedules.create!(service_schedule: evening_schedule, priority: 1)
    tp
  end

  before do
    create(:service_sub_schedule, service_schedule: evening_schedule, day: 1,
           start_time: 17.hours.to_i, end_time: 19.hours.to_i)
  end

  describe ".filter_by_time" do
    it "allows a 9:00 to 19:00 trip when pattern has split coverage" do
      trip_start = 9.hours.to_i
      trip_end   = 19.hours.to_i
      
      result = TravelPattern.filter_by_time(TravelPattern.all, trip_start, trip_end, monday).map(&:id)
      
      expect(result).to include(tp_multi.id)
      expect(result).not_to include(tp_evening_only.id)
    end

    it "does not allow a 9:00 to 16:00 trip with a gap in coverage" do
      trip_start = 9.hours.to_i
      trip_end   = 16.hours.to_i

      result = TravelPattern.filter_by_time(TravelPattern.all, trip_start, trip_end, monday).map(&:id)
      
      expect(result).not_to include(tp_multi.id)
      expect(result).not_to include(tp_evening_only.id)
    end

    it "allows a 17:00 to 18:30 trip on evening-only pattern" do
      trip_start = 17.hours.to_i
      trip_end   = (18.hours + 30.minutes).to_i

      result = TravelPattern.filter_by_time(TravelPattern.all, trip_start, trip_end, monday).map(&:id)
      
      expect(result).to include(tp_evening_only.id)
      expect(result).to include(tp_multi.id)
    end
  end
end
