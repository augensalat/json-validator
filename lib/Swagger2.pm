package Swagger2;

=head1 NAME

Swagger2 - Swagger RESTful API Documentation

=head1 VERSION

0.01

=head1 DESCRIPTION

L<Swagger2> is a module for generating, parsing and transforming
L<swagger|http://swagger.io/> API documentation.

=head1 DEPENDENCIES

=over 4

=item * YAML parser

A L<YAML> parser is required if you want to read/write spec written in
the YAML format. Supported modules are L<YAML::XS>, L<YAML::Syck>, L<YAML>
and L<YAML::Tiny>.

=back

=head1 SYNOPSIS

  use Swagger2;
  my $swagger = Sswagger2->new("file:///path/to/api-spec.yaml");

  # Access the raw specificaiton values
  print $swagger->tree->get("/swagger");

  # Returns the specification as a POD document
  print $swagger->pod->as_string;

=cut

use Mojo::Base -base;
use Mojo::JSON;
use Mojo::JSON::Pointer;
use Mojo::URL;
use Mojo::Util ();

our $VERSION = '0.01';

my @YAML_MODULES = qw( YAML::Tiny YAML YAML::Syck YAML::XS );
my $YAML_MODULE = $ENV{SWAGGER_YAML_MODULE} || (grep { eval "require $_;1" } @YAML_MODULES)[0] || 'Swagger2::__Missing__';

Mojo::Util::monkey_patch(__PACKAGE__, LoadYAML => eval "\\\&$YAML_MODULE\::Load" || sub {die "Need to install a YAML module: @YAML_MODULES"});
Mojo::Util::monkey_patch(__PACKAGE__, DumpYAML => eval "\\\&$YAML_MODULE\::Dump" || sub {die "Need to install a YAML module: @YAML_MODULES"});

=head1 ATTRIBUTES

=head2 base_url

  $mojo_url = $self->base_url;

L<Mojo::URL> object that holds the location to application.

=head2 tree

  $pointer = $self->tree;
  $self = $self->tree(Mojo::JSON::Pointer->new({}));

Holds a L<Mojo::JSON::Pointer> object. This attribute will be built from
L</load>, if L</url> is set.

=head2 ua

  $ua = $self->ua;
  $self = $self->ua(Mojo::UserAgent->new);

A L<Mojo::UserAgent> used to fetch remote documentation.

=head2 url

  $mojo_url = $self->url;

L<Mojo::URL> object that holds the location to the documentation file.
Note: This might also just be a dummy URL to L<http://example.com/>.

=cut

has base_url => sub {
  my $self = shift;
  my $url = Mojo::URL->new;
  my $schemes = $self->tree->get('/schemes');
  my $v;

  $url->host($self->tree->get('/host') || 'example.com');
  $url->path($self->tree->get('/basePath') || '/');
  $url->scheme($schemes->[0] || 'http');

  return $url;
};

has tree => sub {
  my $self = shift;

  $self->load if $self->url;
  $self->{tree} || Mojo::JSON::Pointer->new({});
};

has ua => sub {
  require Mojo::UserAgent;
  Mojo::UserAgent->new;
};

sub url { shift->{url} }

=head1 METHODS

=head2 load

  $self = $self->load;

Used to load the content from C</url>.

=cut

sub load {
  my $self = shift;
  my $scheme = $self->{url}->scheme || 'file';
  my $tree = {};
  my $data;

  $self->{url} = Mojo::URL->new(shift) if @_;

  if ($scheme eq 'file') {
    $data = Mojo::Util::slurp($self->{url}->path);
  }
  else {
    $data = $self->ua->get($self->{url})->res->body;
  }

  if ($self->{url}->path =~ /\.yaml/) {
    $tree = LoadYAML($data);
  }
  elsif ($self->{url}->path =~ /\.json/) {
    $tree = Mojo::JSON::decode_json($data);
  }

  $self->{tree} = Mojo::JSON::Pointer->new($tree);
  $self;
}

=head2 new

  $self = Swagger2->new($url);
  $self = Swagger2->new(%attributes);
  $self = Swagger2->new(\%attributes);

Object constructor.

=cut

sub new {
  my $class = shift;
  my $url = @_ % 2 ? shift : '';
  my $self = $class->SUPER::new(url => $url, @_);

  $self->{url} = Mojo::URL->new($self->{url});
  $self;
}

=head2 pod

  $pod_object = $self->pod;

Returns a L<Swagger2::POD> object.

=cut

sub pod {
  my $self = shift;
  my $resolved = Mojo::JSON::Pointer->new({});
  require Swagger2::POD;
  $self->_resolve_refs($self->tree, $resolved);
  Swagger2::POD->new(base_url => $self->base_url, tree => $resolved);
}

=head2 to_string

  $json = $self->to_string;
  $json = $self->to_string("json");
  $yaml = $self->to_string("yaml");

This method can transform this object into Swagger spec.

=cut

sub to_string {
  my $self = shift;
  my $format = shift || 'json';

  if ($format eq 'yaml') {
    return DumpYAML($self->tree->data);
  }
  else {
    return Mojo::JSON::encode_json($self->tree->data);
  }
}

sub _get_definition {
  my ($self, $path) = @_;
  my $definition = $self->tree->get($path);

  if (!$definition) {
    die "Undefined definition at path: $path";
  }

  if (ref $definition->{required} eq 'ARRAY') {
    for my $name (@{$definition->{required}}) {
      $definition->{properties}{$name}{required} = Mojo::JSON->true;
    }
  }

  return $definition->{properties};
}

sub _resolve_refs {
  my ($self, $in, $out) = @_;

  if (!ref $in eq 'HASH') {
    return $in;
  }

  if (my $ref = $in->{'$ref'}) {
    return $self->_get_definition("/$1") if $ref =~ m!^\#/(.*)!;
    return $self->_get_definition("/definitions/$1") if $ref =~ m!^(\w+)$!;
    die "Not yet supported ref: '$ref'";
  }

  for my $k (keys %$in) {
    my $v = $in->{$k};
    $out->{$k} = ref $v eq 'HASH' ? $self->_resolve_refs($v, {}) : $v;
  }

  return $out;
}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;