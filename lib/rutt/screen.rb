module Rutt
  module Screen
    class Base
      def initialize(stdscr)
        @stdscr = stdscr

        @min_y = 1
        @max_y = @stdscr.getmaxy - 5

        @cur_y = 1
        @cur_x = 0

        @pages = []
        @cur_page = 0
      end

      def incr_page
        check_page = @cur_page + 1
        check_page = @cur_page if check_page >= @pages.length
        @cur_page = check_page
      end

      def decr_page
        @cur_page -= 1
        @cur_page = 0 if @cur_page < 0
      end

      def display_menu
        @stdscr.clear
        @stdscr.move(0, 0)
        @stdscr.addstr(" rutt #{@menu}\n")
      end

      def move_pointer(pos, move_to=false)
        @stdscr.move(@cur_y, 0)
        @stdscr.addstr(" ")

        if move_to == true
          @cur_y = pos
        else
          @cur_y += pos
        end

        @stdscr.move(@cur_y, 0)
        @stdscr.addstr(">")
      end
    end
  end
end
