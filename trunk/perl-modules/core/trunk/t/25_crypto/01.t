use strict;
use warnings;
use Data::Dumper;
use Test;
BEGIN { plan tests => 3 };

print STDERR "OpenXPKI::Crypto::TokenManager\n";

use OpenXPKI::Crypto::TokenManager;

our $cache;
eval `cat t/25_crypto/common.pl`;

ok(1);

my $mgmt = OpenXPKI::Crypto::TokenManager->new ();
ok (1);

## parameter checks for get_token

my $token = $mgmt->get_token (
   TYPE => "CA", 
   ID => "INTERNAL_CA_1", 
   PKI_REALM => "Test Root CA");
ok (defined $token);

1;
