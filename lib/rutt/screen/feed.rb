module Rutt
  module Screen
    class Feed < Base
      def initialize(stdscr)
        super(stdscr)

        @menu = "q:Quit d:delete r:refresh all"

        get_feeds
      end

      def get_feeds
        @feeds = DB::Feed::all
        @pages = @feeds / @max_y
      end

      def display_feeds
        @cur_y = @min_y

        @pages[@cur_page].each do |feed|
          #     next if feed['unread'] == 0  # This should be configurable: feed.showread

          @stdscr.move(@cur_y, 0)
          @stdscr.addstr("  #{feed['unread']}/#{feed['num_items']}\t\t#{feed['title']}\n")

          @cur_y += 1
        end

        @cur_y = @min_y
        @stdscr.refresh
      end

      def window
        @stdscr.clear

        display_menu
        display_feeds
        move_pointer(0)
      end

      def loop
        window

        while true do
          c = @stdscr.getch

          if c > 0 && c < 255
            case c.chr
            when /q/i
              break
            when /a/i
              # no-op
            when /r/i
              cur_y = @cur_y

              DB::Feed::refresh

              window
              move_pointer(cur_y, move_to=true)
            when /d/i
              cur_y = @cur_y - 1

              @stdscr.clear
              display_menu
              feed = @feeds[cur_y]
              @stdscr.move(2, 0)
              @stdscr.addstr("Are you sure you want to delete #{feed['title']}? ")
              d = @stdscr.getch
              DB::Feed::delete(feed) if d.chr =~ /y/i
              window
              move_pointer(cur_y, move_to=true)
            when /p/i
              decr_page
              window
            when /n/i
              incr_page
              window
            when / /
              cur_y = @cur_y
              @stdscr.addstr("#{@pages[@cur_page][cur_y]}")
              item_screen = Item.new(@stdscr, @pages[@cur_page][cur_y - 1])
              item_screen.loop

              get_feeds
              window
              move_pointer(cur_y, move_to=true)
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
