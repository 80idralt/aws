#!/bin/bash
# WordPress keeps its own address in the database (siteurl and home). Point it at the
# load balancer before the servers go behind it, otherwise every page redirects to the
# old server. Run ON novatrix-web, it asks for the database password.
ALB_DNS="<DNS name of novatrix-alb>"
DB_HOST="<DbEndpoint from the data stack>"

mysql -h "$DB_HOST" -u admin -p -e \
  "UPDATE wordpress.wp_options SET option_value='http://$ALB_DNS' WHERE option_name IN ('siteurl','home');"

# Check
mysql -h "$DB_HOST" -u admin -p -e \
  "SELECT option_name, option_value FROM wordpress.wp_options WHERE option_name IN ('siteurl','home');"
