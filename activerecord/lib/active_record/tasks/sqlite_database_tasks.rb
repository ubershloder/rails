# frozen_string_literal: true

module ActiveRecord
  module Tasks # :nodoc:
    class SQLiteDatabaseTasks # :nodoc:
      def self.using_database_configurations?
        true
      end

      def initialize(db_config, root = ActiveRecord::Tasks::DatabaseTasks.root, connection_class: ActiveRecord::Base)
        @db_config = db_config
        @root = root
        @connection_class = connection_class
      end

      def establish_connection
        connection_class.establish_connection(db_config)
      end

      def connection
        # falls back to Base
        ActiveRecord::TemporaryConnection.current_connection
      end

      def create
        raise DatabaseAlreadyExists if File.exist?(db_config.database)

        establish_connection
        connection
      end

      def drop
        require "pathname"
        path = Pathname.new(db_config.database)
        file = path.absolute? ? path.to_s : File.join(root, path)

        FileUtils.rm(file)
      rescue Errno::ENOENT => error
        raise NoDatabaseError.new(error.message)
      end

      def purge
        drop
        connection.disconnect!
      rescue NoDatabaseError
      ensure
        create
        connection.reconnect!
      end

      def charset
        connection.encoding
      end

      def structure_dump(filename, extra_flags)
        args = []
        args.concat(Array(extra_flags)) if extra_flags
        args << db_config.database

        ignore_tables = ActiveRecord::SchemaDumper.ignore_tables
        if ignore_tables.any?
          ignore_tables = connection.data_sources.select { |table| ignore_tables.any? { |pattern| pattern === table } }
          condition = ignore_tables.map { |table| connection.quote(table) }.join(", ")
          args << "SELECT sql FROM sqlite_master WHERE tbl_name NOT IN (#{condition}) ORDER BY tbl_name, type DESC, name"
        else
          args << ".schema"
        end
        run_cmd("sqlite3", args, filename)
      end

      def structure_load(filename, extra_flags)
        flags = extra_flags.join(" ") if extra_flags
        `sqlite3 #{flags} #{db_config.database} < "#{filename}"`
      end

      private
        attr_reader :db_config, :root, :connection_class

        def run_cmd(cmd, args, out)
          fail run_cmd_error(cmd, args) unless Kernel.system(cmd, *args, out: out)
        end

        def run_cmd_error(cmd, args)
          msg = +"failed to execute:\n"
          msg << "#{cmd} #{args.join(' ')}\n\n"
          msg << "Please check the output above for any errors and make sure that `#{cmd}` is installed in your PATH and has proper permissions.\n\n"
          msg
        end
    end
  end
end
