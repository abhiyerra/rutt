module Rutt

  module Feed
    extend self

    def make_table!
      $db.execute(%{
         create table if not exists feeds (
                      id integer PRIMARY KEY,
                      title text,
                      url text,
                      update_interval integer default 3600,
                      created_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      updated_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      UNIQUE(url))
      })
    end

    def add(url, refresh=true)
      $db.execute("insert or ignore into feeds (url) values ('#{url}')")
      $db.execute("select * from feeds where id = (select last_insert_rowid())") do |feed|
        refresh_for(feed)
      end if refresh
    end

    def get(id)

    end

    def delete(feed)
      $db.execute("delete from items where feed_id = ?", feed['id'])
      $db.execute("delete from feeds where id = ?", feed['id'])
    end

    def all(min_limit=0, max_limit=-1)
      $db.execute(%{
       select f.*,
              (select count(*) from items iu where iu.feed_id = f.id) as num_items,
              (select count(*) from items ir where ir.read = 0 and ir.feed_id = f.id) as unread
       from feeds f where unread > 0 order by id desc limit #{min_limit},#{max_limit}
    })
    end

    def refresh
      feeds = $db.execute("select * from feeds")
      results = Parallel.map(feeds, :in_threads => 8) do |feed|
        refresh_for(feed)
      end
    end

    def refresh_for(feed)
      content = open(feed['url']).read
      rss = FeedParser::Feed::new(content)

      puts rss.title

      $db.execute("update feeds set title = ? where id = ?", rss.title, feed['id'])

      rss.items.each do |item|
        $db.execute("insert or ignore into items (feed_id, title, url, published_at) values (?, ?, ?, ?)", feed['id'], item.title, item.link, item.date.to_i)
      end
    rescue Exception => e
      # no-op
    end

    def unread(feed_id)
      $db.execute("select * from items where feed_id = ? and read = 0", feed)
    end

    def mark_as_read(feed)
      $db.execute("update items set read = 1 where feed_id = ?", feed['id'])
    end
  end
end
