module ApplicationHelper
  def format_vietnam_time(time)
    return "N/A" if time.blank?

    time.in_time_zone("Asia/Ho_Chi_Minh").strftime("%b %d, %Y, %H:%M:%S GMT+7")
  end
end
