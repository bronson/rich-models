require File.dirname(__FILE__) + '/../../lib/hobofields'
class HoboMigrationGenerator < Rails::Generator::Base

  def initialize(runtime_args, runtime_options = {})
    super
    @migration_name = runtime_args.first || begin
                                              existing = Dir["#{RAILS_ROOT}/db/migrate/*hobo_migration*"]
                                              max = existing.grep(/([0-9]+)\.rb$/) { $1.to_i }.max
                                              n = max ? max + 1 : 1
                                              "hobo_migration_#{n}"
                                            end
  end

  def migrations_pending?
    pending_migrations = ActiveRecord::Migrator.new(:up, 'db/migrate').pending_migrations

    if pending_migrations.any?
      puts "You have #{pending_migrations.size} pending migration#{'s' if pending_migrations.size > 1}:"
      pending_migrations.each do |pending_migration|
        puts '  %4d %s' % [pending_migration.version, pending_migration.name]
      end
      true
    else
      false
    end
  end


  def manifest
    return record {|m| } if migrations_pending?

    generator = HoboFields::MigrationGenerator.new(self)
    up, down = generator.generate

    if up.blank?
      puts "Database and models match -- nothing to change"
      return record {|m| }
    end

    puts "\n---------- Up Migration ----------", up, "----------------------------------"
    puts "\n---------- Down Migration --------", down, "----------------------------------"

    action = options[:action] || input("What now: [g]enerate migration, generate and [m]igrate now or [c]ancel?", /^(g|m|c)$/)

    if action == 'c'
      # record nothing to keep the generator happy
      record {|m| }
    else
      puts "\nMigration filename:", "(you can type spaces instead of '_' -- every little helps)"
      migration_name = input("Filename [#@migration_name]:", /^[a-z0-9_ ]*$/).strip.gsub(' ', '_') unless options[:default_name]
      migration_name = @migration_name if migration_name.blank?

      at_exit { rake_migrate } if action == 'm'

      up.gsub!("\n", "\n    ")
      up.gsub!(/ +\n/, "\n")
      down.gsub!("\n", "\n    ")
      down.gsub!(/ +\n/, "\n")

      record do |m|
        m.migration_template 'migration.rb', 'db/migrate',
                             :assigns => { :up => up, :down => down, :migration_name => migration_name.camelize },
                             :migration_file_name => migration_name
      end
    end
  rescue HoboFields::FieldSpec::UnknownSqlTypeError => e
    puts "Invalid field type: #{e}"
    record {|m| }
  end


  def extract_renames!(to_create, to_drop, kind_str, name_prefix="")
    return {} if options[:force_drop]

    to_rename = {}
    rename_to_choices = to_create
    to_drop.dup.each do |t|
      while true
        if rename_to_choices.empty?
          puts "\nCONFIRM DROP! #{kind_str} #{name_prefix}#{t}"
          resp = input("Enter 'drop #{t}' to confirm or press enter to keep:")
          if resp.strip == "drop " + t.to_s
            break
          elsif resp.strip.empty?
            to_drop.delete(t)
            break
          else
            next
          end
        else
          puts "\nDROP, RENAME or KEEP?: #{kind_str} #{name_prefix}#{t}"
          puts "Rename choices: #{to_create * ', '}"
          resp = input("Enter either 'drop #{t}' or one of the rename choices or press enter to keep:")
          resp.strip!

          if resp == "drop " + t
            # Leave things as they are
            break
          else
            resp.gsub!(' ', '_')
            to_drop.delete(t)
            if rename_to_choices.include?(resp)
              to_rename[t] = resp
              to_create.delete(resp)
              rename_to_choices.delete(resp)
              break
            elsif resp.empty?
              break
            else
              next
            end
          end
        end
      end
    end
    to_rename
  end


  def input(prompt, format=nil)
    print(prompt + " ")
    if format
      while (response = STDIN.readline.strip.downcase) !~ format
        print(prompt + " ")
      end
      response
    else
      STDIN.readline
    end
  end

  def rake_migrate
    if RUBY_PLATFORM =~ /mswin32/
      system "rake.bat db:migrate"
    else
      system "rake db:migrate"
    end
  end

  protected
    def banner
      "Usage: #{$0} #{spec.name} [<migration-name>]"
    end

    def add_options!(opt)
      opt.separator ''
      opt.separator 'Options:'

      opt.on("--force-drop",   "Don't prompt with 'drop or rename' - just drop everything") { |v| options[:force_drop] = true }
      opt.on("--default-name", "Don't prompt for a migration name - just pick one")         { |v| options[:default_name] = true }
      opt.on("--generate",     "Don't prompt for action - generate the migration")          { |v| options[:action] = 'g' }
      opt.on("--migrate",      "Don't prompt for action - generate and migrate")            { |v| options[:action] = 'm' }
    end


end

