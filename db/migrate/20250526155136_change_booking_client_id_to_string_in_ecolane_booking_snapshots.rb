class ChangeBookingClientIdToStringInEcolaneBookingSnapshots < ActiveRecord::Migration[5.0]
  def change
    change_column :ecolane_booking_snapshots, :booking_client_id, :string
  end
end