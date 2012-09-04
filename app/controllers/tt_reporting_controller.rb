class TtReportingController < ApplicationController
  unloadable

  menu_item :time_tracker_menu_tab_reporting

  helper :queries
  include QueriesHelper
  helper :sort
  include SortHelper
  include TimeTrackersHelper

  def index
    tt_retrieve_query
    # overwrite the initial column_names cause if no columns are specified, the Query class uses default values
    # which depend on issues
    @query.column_names = @query.column_names || [:project, :tt_booking_date, :get_formatted_start_time, :get_formatted_stop_time, :issue, :comments, :get_formatted_time]

    # temporarily limit the available filters and columns for the view!
    @query.available_filters.delete_if { |key, value| !key.to_s.start_with?('tt_') }
    @query.available_columns.delete_if { |item| !([:id, :user, :project, :tt_booking_date, :get_formatted_start_time, :get_formatted_stop_time, :issue, :comments, :get_formatted_time].include? item.name) }

    sort_init(@query.sort_criteria.empty? ? [['tt_booking_date', 'desc']] : @query.sort_criteria)
    sort_update(@query.sortable_columns)

    if @query.valid?
      @limit = per_page_option

      @booking_count = @query.booking_count
      @booking_pages = Paginator.new self, @booking_count, @limit, params['page']
      @offset ||= @booking_pages.current.offset
      @bookings = @query.bookings(:order => sort_clause,
                                  :offset => @offset,
                                  :limit => @limit)
      @booking_count_by_group = @query.booking_count_by_group


      unless @bookings.empty?
        # if the user changes the date-order for the table values, we have to get the correct date, as starting-point for the chart
        @chart_start_date = [@bookings.last.started_on.to_date, @bookings.first.started_on.to_date].min
        # prepare hash for different users
        users = Hash.new
        user_filter = @query.filters["tt_user"]
        if user_filter.nil?
          User.all.each do |user|
            users[user.id] = [] # todo check permissions
          end
        else
          user_filter[:values] += User.current.id.to_s.to_a if user_filter[:values].delete('me')

          if user_filter[:operator] == "!"
            User.all.each do |user| # todo check permissions
              users[user.id] = [] unless user_filter[:values].include?(user.id.to_s)
            end
          elsif user_filter[:operator] == "="
            user_filter[:values].each do |user_id|
              users[user_id.to_i] = [] unless User.where(:id => user_id).first.nil? # todo also check permissions
            end
          end
        end

        # if the user changes the date-order for the table values, we have to sort the data correctly
        # so we create a dynamical method-call
        if @bookings.last.started_on <= @bookings.first.started_on
          m1 = :last
          m2 = :first
        else
          m1 = :first
          m2 = :last
        end

        (@bookings.send(m1).started_on.to_date..@bookings.send(m2).started_on.to_date).map do |date|
          users.keys.each do |key|
            users[key].push(0)
          end
          @bookings.each do |tb|
            users[tb.user.id][users[tb.user.id].size - 1] += tb.hours_spent if tb.started_on.to_date == date
          end
        end
        @chart_data = users
      end

      render :template => 'tt_reporting/index'
    else
      render :template => 'tt_reporting/index'
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end


def self.total_booked_on(date)
  tb_list = where("date(started_on) = ?", date).all
  hours = 0
  tb_list.each do |tb|
    hours += tb.hours_spent
  end
  hours
end