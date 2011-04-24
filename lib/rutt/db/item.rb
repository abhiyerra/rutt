module Rutt
  module Item

    extend self

    def make_table!
      $db.execute(%{
      create table if not exists items (
                      id integer PRIMARY KEY,
                      feed_id integer,
                      title text,
                      url text,
                      description text,
                      read int default 0,
                      prioritize int default 0,
                      published_at DATE NOT NULL DEFAULT (datetime('now','localtime')),
                      created_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      updated_at NOT NULL DEFAULT CURRENT_TIMESTAMP,
                      UNIQUE(url),
                      FOREIGN KEY(feed_id) REFERENCES feeds(id))
    })
    end

    def all(feed, min_limit=0, max_limit=-1)
      $db.execute("select * from items where feed_id = ? order by published_at desc limit #{min_limit},#{max_limit}", feed['id'])
    end

    def mark_as_unread(item)
      $db.execute("update items set read = 0 where id = #{item['id']}")
    end

    def mark_as_read(item)
      $db.execute("update items set read = 1 where id = #{item['id']}")
    end

    def sent_to_instapaper(item)
      $db.execute("update items set read = 2 where id = #{item['id']}")
    end
  end
end
