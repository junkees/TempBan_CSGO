# Простенькая система банов, работающая с mysql. 

Писалась очень давно и работает не совсем корректно.

Команды
* !tempban nick time reason
* !untempban nick reason

addons/sourcemod/configs/databases.cfg
``` "tempban_spec"
        {
                "driver"        "mysql"
                "host"  ""
                "database"      ""
                "user"  ""
                "pass"  ""
                "port"  "3306"
        } ```
