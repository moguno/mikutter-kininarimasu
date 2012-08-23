# -*- coding: utf-8 -*-

require 'date'

Plugin.create :kininarimasu do 

  UserConfig[:interest_keyword] ||= ""
  UserConfig[:interest_japanese] ||= true
  UserConfig[:interest_period] ||= 60

  settings "わたし、気になります" do
    input("検索キーワード", :interest_keyword)
    boolean("日本語のツイートのみ", :interest_japanese)
    adjustment("ポーリング間隔（秒）", :interest_period, 10, 600)
  end 

  def main(service)
    Reserver.new(UserConfig[:interest_period]){
      search_keyword(service)
      sleep 1
      main service
    } 
  end

  on_boot do |service|
    main service
  end

  def search_keyword(service)

    if UserConfig[:interest_keyword].empty? then
      return
    end

    params = {}

    params[:q] = UserConfig[:interest_keyword]

    if UserConfig[:interest_japanese] then
      params[:lang] = "ja"
    end

    service.search(params).next{ |res| 
      res = res.map { |es| 
        es[:created] = Time.now
        es
      }

      timeline(:home_timeline) << res
    }
  end

end
