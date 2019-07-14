# Getting embedding working in WordPress

Don't need to mess around with HTML. WP supports automatic embedding if writer just pastes the page URL into the block.

https://wordpress.org/support/article/embeds/#adding-support-for-an-oembed-enabled-site - might be able to get away without registering if we provide an iframe (or if WP wraps it in one - unclear)
https://codex.wordpress.org/Function_Reference/wp_oembed_add_provider

https://oembed.com/ - looks quite simple. Particularly of interest is sect 4 - Discovery and 2.3.4.4 - The rich type. Once we have proper domain and it running we can register to be official provider and it should work in quite a few places.

# Deploying this

#. Stop all containers
#. Back-up volumes (persistent data) from local host via https://github.com/loomchild/volume-backup 
    #. See https://github.com/loomchild/volume-backup#user-content-copy-volume-between-hosts esp
    #. `docker volume ls` will show you the ones you need
#. Clone this repo
#. Copy .env to new box securely
#. Change URL in docker-compose
#. `docker-compose up -d` on new box
#. Change URL in wordpress via admin panel
