# -*- coding: utf-8 -*-
  
require 'date'
  
Plugin.create :kininarimasu do 
  
  # コンフィグの初期化
  UserConfig[:interest_keyword1] ||= ""
  UserConfig[:interest_keyword2] ||= ""
  UserConfig[:interest_keyword3] ||= ""
  UserConfig[:interest_keyword4] ||= ""
  UserConfig[:interest_keyword5] ||= ""
  UserConfig[:interest_japanese] ||= true
  UserConfig[:interest_period] ||= 60
  UserConfig[:interest_insert_period] ||= 3
  UserConfig[:interest_prefix] ||= ""
  

  # グローバル変数の初期化
  $result_queue = []
  $last_time = nil
  $last_keyword = ""
  

  # 設定画面
  settings "わたし、気になります" do
    settings "検索ワード" do
      input("", :interest_keyword1)
      input("", :interest_keyword2)
      input("", :interest_keyword3)
      input("", :interest_keyword4)
      input("", :interest_keyword5)
    end
 
    boolean("日本語のツイートのみ", :interest_japanese)
    adjustment("ポーリング間隔（秒）", :interest_period, 1, 6000)
    adjustment("混ぜ込み間隔（秒）", :interest_insert_period, 1, 600)
    input("プレフィックス", :interest_prefix)
  end 
  
  
  # 検索キーワード文字列の生成
  def get_query_keyword()
    [:interest_keyword1, :interest_keyword2, :interest_keyword3, :interest_keyword4, :interest_keyword5]
    .select{ |key| !UserConfig[key].empty? }
    .map{ |key| UserConfig[key] }
    .join("+OR+")
  end
  
  
  # 検索用ループ
  def search_loop(service)
    Reserver.new(UserConfig[:interest_period]){
      keywords = search_keyword(service) 
      search_loop service
    } 
  end
  
  
  # 混ぜ込みループ
  def insert_loop(service)
    Reserver.new(UserConfig[:interest_insert_period]){
      begin
        if $result_queue.size != 0 then
          msg = $result_queue.shift

          msg[:created] = Time.now
  
          if !UserConfig[:interest_prefix].empty? then
            msg[:message] = UserConfig[:interest_prefix] + " " + msg[:message]
          end
  
          msg.user[:created] ||= Time.now

          if defined?(timeline)
            timeline(:home_timeline) << [msg]
          else
            Plugin.call(:update, service, [msg])
          end

          #  p "last message :" + $result_queue.size.to_s
        end

        insert_loop service

      rescue=>e
        puts e.backtrace
      end
    } 
  end
  

  # 起動時処理
  on_boot do |service|
    search_loop service
    insert_loop service
  end
  
  
  # 検索
  def search_keyword(service)
    query_keyword = get_query_keyword()
  
    # p query_keyword
  
    if query_keyword.empty? then
      return
    end
  
    params = {}
  
    params[:q] = query_keyword
    params[:rpp] = "100"
  
    if UserConfig[:interest_japanese] then
      params[:lang] = "ja"
    end
  
    service.search(params).next{ |res| 
      begin
        if $last_keyword != query_keyword then
          $last_time = nil
          $result_queue.clear
        end
  
        $last_keyword = query_keyword
  
        res = res.select { |es|
          if es[:message] =~ /^RT / then
            false
          else
            if $last_time == nil then
              true
            elsif $last_time < Time.parse(es[:created_at]) then
              true
            else
              false
            end 
          end
        }
  
        if res.size == 0 then
          next
        end
  
        res.each { |es| 
          tim = Time.parse(es[:created_at])
  
          if $last_time == nil || $last_time < tim then
            $last_time = tim
          end
        }
  
        # p "new message:" + res.size.to_s
        # p "last time:" + $last_time.to_s
  
        $result_queue.concat(res.reverse)
      rescue => e
        puts e.backtrace
      end
    }
  end
end
