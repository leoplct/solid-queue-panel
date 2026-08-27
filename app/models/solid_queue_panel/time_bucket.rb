# frozen_string_literal: true

module SolidQueuePanel
  # Groups timestamps into fixed size buckets, in SQL when the adapter allows it
  # and in Ruby otherwise. This is what feeds the dashboard chart without
  # loading a day worth of timestamps into memory.
  class TimeBucket
    # Safety net for adapters we cannot bucket in SQL: never load more rows than
    # this when falling back to grouping in Ruby.
    RUBY_FALLBACK_LIMIT = 50_000

    attr_reader :size

    def initialize(size)
      @size = size.to_i.clamp(1, 1.day.to_i)
    end

    # Returns a Hash of bucket index (epoch / size) to number of records.
    def count(relation, column)
      expression = sql_expression(relation.model, column)

      if expression
        relation.group(Arel.sql(expression)).count.transform_keys(&:to_i)
      else
        count_in_ruby(relation, column)
      end
    end

    def index_for(time)
      time.to_i / size
    end

    def time_for(index)
      Time.zone.at(index * size)
    end

    private
      def sql_expression(model, column)
        model.connection_pool.with_connection do |connection|
          quoted = [ connection.quote_table_name(model.table_name), connection.quote_column_name(column) ].join(".")

          case connection.adapter_name.downcase
          when /postgres/ then "FLOOR(EXTRACT(EPOCH FROM #{quoted}) / #{size})"
          when /mysql|trilogy/ then "FLOOR(UNIX_TIMESTAMP(#{quoted}) / #{size})"
          when /sqlite/ then "CAST(STRFTIME('%s', #{quoted}) / #{size} AS INTEGER)"
          end
        end
      end

      def count_in_ruby(relation, column)
        relation.limit(RUBY_FALLBACK_LIMIT).pluck(column).each_with_object(Hash.new(0)) do |time, counts|
          counts[index_for(time)] += 1 if time
        end
      end
  end
end
