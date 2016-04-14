use strict;
use warnings;
use JSON;
use PCP::PMDA;
use LWP::UserAgent;


# CONFIG
my $cache_interval = 10;         # min secs between refreshes for clusters
my $http_timeout = 1;            # max secs for a request (*must* be small).
my $host_port = "localhost:8002";# ML host and port
my $user = "admin";              # username
my $pass = "admin";              # password
my $realm = "public";            # realm
# END CONFIG

my %cluster_stats ;
my @cluster_cache;               # cache 

use vars qw($ml_cluster $http $pmda $cache_interval $http_timeout);

my $http = LWP::UserAgent->new;
$http->agent('pdmamarklogic');
$http->timeout($http_timeout);
$http->credentials($host_port, $realm, $user, $pass);


sub ml_fetch_callback
{
    my ($cluster, $item, $inst) = @_;
    my $metric_name = pmda_pmid_name($cluster, $item);
    my ($path, $value, @tokens);

#   $pmda->log("ml_fetch_callback $metric_name $cluster:$item ($inst)\n");

    if ($inst != PM_IN_NULL)	{ return (PM_ERR_INST, 0); }
    if (!defined($metric_name))	{ return (PM_ERR_PMID, 0); }
    @tokens = split("/", $cluster_stats{$metric_name});
    
    my $temp = $ml_cluster;
    foreach my $token (@tokens) {
      $temp = $temp->{$token}  ;
    }
    $value = $temp;
    if (!defined($value))	{ return (PM_ERR_APPVERSION, 0); }
    return ($value, 1);
}


sub ml_get
{
    my $request = shift;
    my $response = $http->get($request);
    my $success = $response->is_success;
    $pmda->log("ml_get request $request: $success");
    return undef unless $success;
    return decode_json($response->decoded_content);
}


sub ml_refresh
{
    my ($cluster) = @_;
    my $now = time;

    if (defined($cluster_cache[$cluster]) &&
        $now - $cluster_cache[$cluster] <= $cache_interval) {
        return;
    }

    if ($cluster == 0) {        # Cluster metrics
         my $request = "http://localhost:8002/manage/v2?view=status&format=json";
         $ml_cluster = ml_get($request); 
    } 
    $cluster_cache[$cluster] = $now;
};

sub ml_add_metric 
{
   my ($count, $base, $pref, $metric) = @_;
   (my $name = $metric)  =~ s/-/_/g;
   $pmda->add_metric(pmda_pmid(0,$count), PM_TYPE_FLOAT, PM_INDOM_NULL, 
                  PM_SEM_INSTANT, pmda_units(0,0,1,0,0,PM_COUNT_ONE), 
                  'marklogic.cluster.'. $pref. $name, $name , '');
   $cluster_stats{'marklogic.cluster.' . $pref. $name} = $base. $metric . '/value';
}



$pmda = PCP::PMDA->new('marklogic', 155);
$pmda->connect_pmcd;

my $count=0;
$pmda->add_metric(pmda_pmid(0,$count++), PM_TYPE_STRING, PM_INDOM_NULL, 
                  PM_SEM_INSTANT, pmda_units(0,0,0,0,0,0), 
                  'marklogic.cluster.name', 'Name of MarkLogic cluster', '');
$cluster_stats{'marklogic.cluster.name'} = 'local-cluster-status/name';



foreach my $metric ("total-hosts")
{
  ml_add_metric($count++, 'local-cluster-status/status-relations/hosts-status/hosts-status-summary/', '', $metric);
}

foreach my $metric ("expanded-tree-cache-hit-rate", "expanded-tree-cache-miss-rate", "request-rate", "request-count")
{
  ml_add_metric($count++, 'local-cluster-status/status-relations/servers-status/servers-status-summary/','',  $metric);
}

foreach my $metric ("total-requests", "ninetieth-percentile-seconds","mean-seconds" , "standard-dev-seconds")
{
  ml_add_metric($count++, 'local-cluster-status/status-relations/requests-status/requests-status-summary/', 'requests_', $metric);
}

foreach my $metric ("journal-write-rate", "save-write-rate",
                    "merge-write-rate","merge-read-rate",
                    "write-lock-rate", "read-lock-rate", "deadlock-rate",
                    "memory-system-pageout-rate","memory-system-pagein-rate",
                    "memory-system-swapout-rate","memory-system-swapin-rate",
                    "xdqp-client-send-rate", "xdqp-client-receive-rate",
                    "xdqp-server-send-rate", "xdqp-server-receive-rate",
                    "large-write-rate", "large-read-rate")
{
  ml_add_metric($count++, 'local-cluster-status/status-relations/hosts-status/hosts-status-summary/rate-properties/rate-detail/', '', $metric);
}


foreach my $metric ("journal-write-load", "save-write-load",
                    "merge-write-load","merge-read-load",
                    "write-lock-wait-load", "write-lock-hold-load",
                    "read-lock-wait-load", "read-lock-hold-load",
                    "deadlock-wait-load",
                    "xdqp-client-send-load", "xdqp-client-receive-load",
                    "xdqp-server-send-load", "xdqp-server-receive-load",
                    "large-write-load", "large-read-load")
{
  ml_add_metric($count++, 'local-cluster-status/status-relations/hosts-status/hosts-status-summary/load-properties/load-detail/','', $metric);
}



foreach my $metric ("backup-count", "state-not-open","max-stands-per-forest","merge-count", "restore-count", "total-forests")
{
  ml_add_metric($count++, 'local-cluster-status/status-relations/forests-status/forests-status-summary/', '', $metric);
}

foreach my $metric ("list-cache-miss-rate","list-cache-hit-rate", "list-cache-ratio", 
                    "compressed-tree-cache-miss-rate","compressed-tree-cache-hit-rate", "compressed-tree-cache-ratio")
{
  ml_add_metric($count++, 'local-cluster-status/status-relations/forests-status/forests-status-summary/cache-properties/','', $metric);
}

foreach my $metric ("total-transactions", "ninetieth-percentile-seconds","mean-seconds" , "standard-dev-seconds")
{
  ml_add_metric($count++, 'local-cluster-status/status-relations/transactions-status/transactions-status-summary/', 'transactions_', $metric);
}
$pmda->set_fetch_callback(\&ml_fetch_callback);
$pmda->set_refresh(\&ml_refresh);
$pmda->set_user('pcp');
$pmda->run;


