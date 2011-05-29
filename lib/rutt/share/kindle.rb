module Rutt
  module Share
    class Kindle
      def initialize(feed)

        items = Rutt::DB::Item.unread(feed)

        # TODO: Should be name of feed
        title = "rutt feed"

        puts "<html><head><title>#{title}</title></head><body>"
        puts "<h1>rutt feed</h1>"

        items.each do |item|
          puts "<mbp:pagebreak/>"
          puts "<h2>#{item['title']}</h2>"
          puts ::Readability::Document.new(open(item['url']).read).content
        end
        puts "</body></html>"

        items.each do |item|
          Rutt::DB::Item.mark_as_read(item)
        end
      end
    end

  end
end
