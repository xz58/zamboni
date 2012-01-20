# playdoh-specific commands that get zamboni all going so you don't
# have to.

# TODO: Make this rely on things that are not straight-up exec.
class zamboni {
    package { "wget":
        ensure => installed;
    }

    file { "$PROJ_DIR/settings_local.py":
        ensure => file,
        source => "$PROJ_DIR/docs/settings/settings_local.dev.py",
        replace => false;
    }

    exec { "create_mysql_database":
        command => "mysqladmin -uroot create $DB_NAME",
        unless  => "mysql -uroot -B --skip-column-names -e 'show databases' | /bin/grep '$DB_NAME'",
        require => File["$PROJ_DIR/settings_local.py"]
    }

    exec { "grant_mysql_database":
        command => "mysql -uroot -B -e'GRANT ALL PRIVILEGES ON $DB_NAME.* TO $DB_USER@localhost # IDENTIFIED BY \"$DB_PASS\"'",
        unless  => "mysql -uroot -B --skip-column-names mysql -e 'select user from user' | grep '$DB_USER'",
        require => Exec["create_mysql_database"];
    }

    exec { "fetch_landfill_sql":
        cwd => "$PROJ_DIR",
        command => "wget --no-check-certificate -P /tmp https://landfill.addons.allizom.org/db/landfill-`date +%Y-%m-%d`.sql.gz",
        require => [
            Package["wget"],
            Exec["grant_mysql_database"]
        ];
    }

    exec { "load_data":
        cwd => "$PROJ_DIR",
        command => "zcat /tmp/landfill-`date +%Y-%m-%d`.sql.gz | mysql -u$DB_USER $DB_NAME",
        require => [
            Exec["fetch_landfill_sql"]
        ];
    }

    # TODO(Kumar) add landfile files as well.

    # Skip this migration because it won't succeed without indexes but you
    # can't build indexes without running migrations :(
    file { "$PROJ_DIR/migrations/264-locale-indexes.py":
        content => "#",
        replace => true
    }

    exec { "sql_migrate":
        cwd => "$PROJ_DIR",
        command => "python ./vendor/src/schematic/schematic migrations/",
        require => [
            Service["mysql"],
            Package["python2.6"],
            File["$PROJ_DIR/migrations/264-locale-indexes.py"],
            Exec["fetch_landfill_sql"],
            Exec["load_data"]
        ];
    }

    exec { "restore_migration_264":
        cwd => "$PROJ_DIR",
        command => "git checkout migrations/264-locale-indexes.py",
        require => [Exec["sql_migrate"], Package["git-core"]]
    }

    exec { "remove_site_notice":
        command => "mysql -uroot -e\"delete from config where \\`key\\`='site_notice'\" $DB_NAME",
        require => Exec["sql_migrate"]
    }
}