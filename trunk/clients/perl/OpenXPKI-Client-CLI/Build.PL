use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'OpenXPKI::Client::CLI',
    license             => 'perl',
    dist_author         => 'Martin Bartosch <m.bartosch@cynops.de>',
    dist_version_from   => 'lib/OpenXPKI/Client/CLI.pm',
    requires => {
        'Test::More' => 0,
        'version'    => 0,
        'OpenXPKI'   => '0.9.217',
    },
    add_to_cleanup      => [ 'OpenXPKI-Client-CLI-*' ],
);

$builder->create_build_script();
