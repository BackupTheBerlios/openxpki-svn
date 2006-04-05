use strict;
use warnings;
use Test;
use Data::Dumper;
use Scalar::Util qw( blessed );

# use Smart::Comments;

use OpenXPKI::Server::Init;
use OpenXPKI::Server::Context qw( CTX );
use OpenXPKI::Exception;

BEGIN { plan tests => 47 };

print STDERR "OpenXPKI::Server::Context - pki_realm\n";
ok(1);

## init Context
ok(OpenXPKI::Server::Init->new ({
       CONFIG => 't/config.xml',
   }));


my $realms = CTX('pki_realm');

my $realm = 'Test Root CA';


# check PKI realm data structure
ok(ref $realms->{$realm}, 
   'HASH');

# default token
ok(ref $realms->{$realm}->{crypto}, 
   'HASH');

ok(blessed $realms->{$realm}->{crypto}->{default}, 
   'OpenXPKI::Crypto::Backend::API');

# profile validities
foreach my $profiletype (qw( crl endentity selfsignedca )) {
    ok(ref $realms->{$realm}->{$profiletype},
       'HASH');
    ok(ref $realms->{$realm}->{$profiletype}->{id},
       'HASH');
}

foreach my $profile ('User', 'TLS Server') {
    ok(ref $realms->{$realm}->{endentity}->{id}->{$profile},
       'HASH');

    ok(ref $realms->{$realm}->{endentity}->{id}->{$profile}->{validity},
       'HASH');

    ok(ref $realms->{$realm}->{endentity}->{id}->{$profile}->{validity}->{notafter},
       'HASH');

    ok($realms->{$realm}->{endentity}->{id}->{$profile}->{validity}->{notafter}->{format},
       'relativedate');
}


# CA information
ok(ref $realms->{$realm}->{ca}, 
   'HASH');

ok(ref $realms->{$realm}->{ca}->{id}, 
   'HASH');

foreach my $ca (qw( INTERNAL_CA_1 INTERNAL_CA_2 )) {
    # check for CA certificate and token information
    ok(ref $realms->{$realm}->{ca}->{id}->{$ca}, 
   'HASH');
    
    ok(blessed $realms->{$realm}->{ca}->{id}->{$ca}->{cacert}, 
       'OpenXPKI::Crypto::X509');

    ok(blessed $realms->{$realm}->{ca}->{id}->{$ca}->{notbefore}, 
       'DateTime');

    ok(blessed $realms->{$realm}->{ca}->{id}->{$ca}->{notafter}, 
       'DateTime');

    ok(blessed $realms->{$realm}->{ca}->{id}->{$ca}->{crypto}, 
       'OpenXPKI::Crypto::Backend::API');

    # check for profile validities

    # CRLs
    ok(ref $realms->{$realm}->{crl}->{id}->{$ca}->{validity},
       'HASH');
    ok(! exists $realms->{$realm}->{crl}->{id}->{$ca}->{validity}->{notbefore});
    
    ok(ref $realms->{$realm}->{crl}->{id}->{$ca}->{validity}->{notafter},
       'HASH');
    ok($realms->{$realm}->{crl}->{id}->{$ca}->{validity}->{notafter}->{format},
       'relativedate');
    ok($realms->{$realm}->{crl}->{id}->{$ca}->{validity}->{notafter}->{validity},
       '+000014');

    
    # selfsigned CA validities
    ok(ref $realms->{$realm}->{selfsignedca}->{id}->{$ca}->{validity},
       'HASH');

    # no check for notbefore date, we trust it's OK...
    
    ok(ref $realms->{$realm}->{selfsignedca}->{id}->{$ca}->{validity}->{notafter},
       'HASH');
    ok($realms->{$realm}->{selfsignedca}->{id}->{$ca}->{validity}->{notafter}->{format},
       'relativedate');
    # no check for validity value, trust it's OK
    
}


1;
