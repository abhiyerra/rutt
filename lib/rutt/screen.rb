module Rutt
  module Screen
    class Base
      def initialize(stdscr)
        @stdscr = stdscr

        @min_y = 1
        @max_y = @stdscr.getmaxy

        @min_limit = @min_y - 1
        @max_limit = @max_y - 5

        @cur_y = 1
        @cur_x = 0
      end

      def incr_page
        @min_limit =  @max_limit
        @max_limit += (@max_y - 5)
      end

      def decr_page
        @max_limit =  @min_limit
        @min_limit -= (@max_y - 5)

        if @max_limit <= 0
          @min_limit = @min_y - 1
          @max_limit = @max_y - 5
        end
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
