use strict;
use warnings;
use English;
use Test;
BEGIN { plan tests => 7 };

print STDERR "OpenXPKI::Server::ACL Correctness\n";

use OpenXPKI::Server::Session;
use OpenXPKI::Server::ACL;
ok(1);

## create context
use OpenXPKI::Server::Context qw( CTX );
### instantiating context...
ok(OpenXPKI::Server::Context::create(
       CONFIG => 't/config.xml',
       DEBUG  => 0,
   ));

## create new session
my $session = OpenXPKI::Server::Session->new (
                  DEBUG     => 0,
                  DIRECTORY => "t/50_auth/",
                  LIFETIME  => 5);
ok($session);
ok(OpenXPKI::Server::Context::setcontext(session => $session));

## configure the session
$session->set_pki_realm ("Test Root CA");
$session->set_role ("CA Operator");
$session->make_valid ();
ok($session->is_valid());

## initialize the ACL
my $acl = OpenXPKI::Server::ACL->new();
ok($acl);

## start the real ACL tests

ok($acl->authorize ({ACTIVITYCLASS => "Test::Test",
                     ACTIVITY      => "Test",
                     AFFECTED_ROLE => "User"}));

1;
