# Shared by every environment; loaded automatically on every run.
# Deliberately NO `environment` here: a missing -var-file must fail ("No value for required variable"),
# not silently fall back to one environment.

secret_scope_name = "smogcast"
group_prefix      = "smogcast"

# Voivodeships that get a row-level-security group (jurisdiction_code in conf/cities.yaml of the smogcast repo,
# ISO 3166-2:PL). Only two — enough to show RLS switching between regions: PL-02 dolnośląskie (Wrocław),
# PL-12 małopolskie (Kraków). Any other code of conf/cities.yaml can be added here.
region_codes = ["PL-02", "PL-12"]
