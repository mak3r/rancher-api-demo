# Create rancher clusters
A bash script to use the Ranche API to retrieve the commands needed to create custom clusters or import existing clusters

* Help on all options
    `rancher-cluster.sh -h`

## Examples 

* Create an imported cluster

    `rancher-cluster.sh -i  -k -n "$CLUSTER_NAME" -s https://rancher-demo.mak3r.design -u "$USER_NAME" -p "$ADMIN_SECRET" -x`

    * Creates an import cluster with `$CLUSTER_NAME` and executes the command immediately.
    * Using `-x` implies `kubectl` will run the command returned on the current cluster context.

* Create a custom cluster

    `rancher-cluster.sh -i  -d -c -e -w -n "$CLUSTER_NAME" -s https://rancher-demo.mak3r.design -u "$USER_NAME" -p $"ADMIN_SECRET"`

    * Create a custom cluster with all roles and `$CLUSTER_NAME`
    * Print the docker command to the terminal, don't execute it.