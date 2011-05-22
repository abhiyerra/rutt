module Rutt
  module Screen
    class Item < Base
      def initialize(stdscr, feed)
        super(stdscr)

        @feed = feed
        @menu = " i:quit r:refresh m:mark as read u:mark as unread a:mark all as read b:open in browser"

        get_items
      end

      def get_items
        @items = DB::Item::all(@feed)
        @pages = @items / @max_y
      end

      def display_items
        @cur_y = @min_y

        @pages[@cur_page].each do |item|
          item_status = case item['read'].to_i
                        when 0 then 'N'
                        when 1 then ' '
                        when 2 then 'I'
                        else ' '
                        end
          @stdscr.addstr("  #{item_status}\t#{Time.at(item['published_at']).strftime("%b %d, %Y %R:%M")}\t#{item['title']}\n")
          @cur_y += 1
        end

        @cur_y = @min_y
        @stdscr.refresh
      end

      def window
        @stdscr.clear

        display_menu
        display_items
        move_pointer(0)
      end

      def loop
        window

        while true do
          c = @stdscr.getch

          if c > 0 && c < 255
            case c.chr
            when /[iq]/i
              break
            when /s/i
              cur_y = @cur_y - 1
              $instapaper.request('/api/1/bookmarks/add', {
                  'url'   => @pages[@cur_page][cur_y]['url'],
                  'title' => @pages[@cur_page][cur_y]['title'],
                })
              DB::Item::sent_to_instapaper(@pages[@cur_page][cur_y])
              get_items
              window
              move_pointer(cur_y + 1, move_to=true)
            when /a/i
              DB::Feed::mark_as_read(@feed)
              get_items
              window
              move_pointer(@cur_y, move_to=true)
            when /p/i
              decr_page
              window
            when /n/i
              incr_page
              window
            when /b/i
              cur_y = @cur_y - 1
              DB::Item::mark_as_read(@items[cur_y])
              Launchy.open(@pages[@cur_page][cur_y]['url'])
              window
              move_pointer(@cur_y, move_to=true)
            when /m/i
              cur_y = @cur_y - 1
              DB::Item::mark_as_read(@pages[@cur_page][cur_y])
              get_items
              window
              move_pointer(cur_y + 1, move_to=true)
            when /u/i
              cur_y = @cur_y - 1
              DB::Item::mark_as_unread(@pages[@cur_page][cur_y])
              get_items
              window
              move_pointer(cur_y + 1, move_to=true)
            when /r/i
              DB::Feed::refresh_for(@feed)
              window
            when / /
              cur_y = @cur_y - 1
              content_screen = Content.new(@stdscr, @pages[@cur_page][cur_y])
              content_screen.loop

              get_items
              window
              move_pointer(cur_y + 1, move_to=true)
            end
          else
            case c
            when Ncurses::KEY_UP
              move_pointer(-1)
            when Ncurses::KEY_DOWN
              move_pointer(1)
            end
          end
        end
      end
    end
  end
end
