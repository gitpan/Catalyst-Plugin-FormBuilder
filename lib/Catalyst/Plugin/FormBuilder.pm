
# Copyright (c) 2006 Nate Wiger <nate@wiger.org>. All Rights Reserved.
# For full documentation, use "perldoc Catalyst::Plugin::FormBuilder"

=head1 NAME

Catalyst::Plugin::FormBuilder - Catalyst FormBuilder Plugin

=head1 SYNOPSIS

    package MyApp;
    use Catalyst qw/FormBuilder/;

    package MyApp::Controller::Example;
    use base 'Catalyst::Controller';

    #
    # The simplest example looks for edit.fb to create
    # a form, based on the presence of the ":Form" attribute.
    #
    sub edit : Form {
        my ($self, $c, @args) = @_;
        $c->form->field(name => 'email', validate => 'EMAIL');
        $c->form->messages('/locale/messages.fr');
    }

    #
    # This example references edit still, since we are 
    # just switching to a readonly view. The layout will be
    # the same, but fields are rendered as static HTML.
    #
    sub view : Form('/books/edit') {
        my ($self, $c) = @_;
        $c->form->static(1);      # set form to readonly
    }

=cut

package Catalyst::Plugin::FormBuilder;

our $VERSION = do { my @r=(q$Revision: 1.3 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

use strict;
use warnings;
no  warnings 'uninitialized';
use attributes;
use NEXT;

# Need a newer version of FormBuilder
use CGI::FormBuilder 3.0202;

# Loads our FormBuilder class in $c->form
use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw/form/);

#
# Catalyst loading and dispatching
#
sub prepare {
    my $class = shift;

    # Get all the basics, so we have request parameters
    my $c = $class->NEXT::prepare(@_);

    # Find out what action is handling this request, so
    # we can see whether it needs a form or not. Throw
    # a fatal error if they specified a form, or ignore
    # it otherwise.
    return $c unless exists $c->action->attributes->{Form};
    my $name = $c->action->attributes->{Form}[0];
    my $fatal = 1;
    unless ($name) {
        $name = $c->req->path;
        $fatal = 0;
    }
    $name =~ s#^/+##;

    # Load configured defaults from the user, and add in some
    # custom settings needed to meld FormBuilder with Catalyst
    my $attr = $c->config->{form} || {};
    $attr->{params} = $c->req->params;
    $attr->{action} = '/'.$c->req->path;

    # Attempt to autoload config and template files
    # Cleanup suffix to allow ".fb" or "fb" in config
    my $fbdir = $c->config->{form}{form_path}
             || File::Spec->catfile($c->config->{home}, 'root', 'forms');
    my $fbsuf = $c->config->{form}{form_suffix} || 'fb';
    $fbsuf =~ s/^\.*//;
    $c->log->debug("Form ($name): Looking for form config in $fbdir");
    my $fbfile = "$name.$fbsuf";

    # Look for files relative to our current action url (/books/edit)
    for my $dir (split /\s*:\s*/, $fbdir) {
        my $conf = File::Spec->catfile($dir, $fbfile);
        if (-f $conf && -r _) {
            $c->log->debug("Form ($name): Found form config $conf");
            $attr->{source} = $conf;
        }
    }

    # Throw an error if the file was manually specified, or just
    # log a warning message otherwise.
    unless ($attr->{source}) {
        if ($fatal) {
            $c->error("Form ($name): Can't find form config $fbfile in $fbdir: $!");
        } else {
            $c->log->warn("Form ($name): Can't access form config $fbfile in $fbdir: $!");
        }
    }

    # Arg cleanup
    delete $attr->{form_path};
    delete $attr->{form_suffix};

    # Create and cache form in main $c context
    $attr->{debug} = $c->log->is_debug ? 2 : 0;
    $c->stash->{form} = $c->{form} = CGI::FormBuilder->new($attr);

    return $c;
}

1;

__END__

=head1 DESCRIPTION

This plugin merges the functionality of B<CGI::FormBuilder> with Catalyst
and Template Toolkit. This gives you access to all of FormBuilder's niceties,
such as controllable field stickiness, multilingual support, and Javascript
generation. For more details, see L<CGI::FormBuilder> or the website at:

    http://www.formbuilder.org

FormBuilder usage within Catalyst is straightforward. Since Catalyst handles
page rendering, you don't call FormBuilder's C<render()> method, as you 
would normally. Instead, you simply add a C<:Form> attribute to each method
that you want to associate with a form. This will give you access to a 
FormBuilder C<< $c->form >> object within that controller method:

    # An editing screen for books
    sub edit : Form {
        # The file books/edit.fb is loaded automatically
        $c->form->method('post');   # set form method
    }

The out-of-the-box setup is to look for a form configuration file that follows
the L<CGI::FormBuilder::Source::File> format (essentially YAML), named for the
current action url. So, if you were serving C</books/edit>, this plugin
would look for:

    root/forms/books/edit.fb

(The path is configurable.) If no source file is found, then it is assumed
you'll be setting up your fields manually. In your controller, you will
have to use the C<< $c->form >> object to create your fields, validation,
and so on.

Here is an example C<edit.fb> file:

    # Form config file root/forms/books/edit.fb
    name: books_edit
    method: post
    fields:
        title:
            label: Book Title
            type:  text
            size:  40
            required: 1
        author:
            label: Author's Name
            type:  text
            size:  80
            validate: NAME
            required: 1
        isbn:
            label: ISBN#
            type:  text
            size:  20
            validate: /^(\d{10}|\d{13})$/
            required: 1
        desc:
            label: Description
            type:  textarea
            cols:  80
            rows:  5
        country:
            label: Country of Origin
            type:  select
            required: 1

    submit: Save New Book

This will automatically create a complete form for you, using the
specified fields. Note that the C<root/forms> path is configurable;
this path is used by default to integrate with the C<TTSite> helper.

The FormBuilder methodolody is to handle both rendering and validation
of the form. As such, the form will "loop back" onto the same controller
method. Within your controller, you would then use the standard FormBuilder
submit/validate check:

    if ($c->form->submitted && $c->form->validate) {
        $c->forward('/books/save');
    }

This would forward to C</books/save> if the form was submitted and
passed field validation. Otherwise, it would automatically re-render the
form with invalid fields highlighted, leaving the database unchanged.

Within your controller, you can call any method that you would on a
normal C<CGI::FormBuilder> object on the C<< $c->form >> object.
To manipulate the field named C<desc>, simply call the C<field()>
method:

    # Change our desc field dynamically
    $c->form->field(name  => 'desc',
                    label => 'Book Description',
                    required => 1);

To populate field options for C<country>, you might use something like
this to iterate through the database:

    $c->form->field(name    => 'country',
                    options => [ map { $_->id, $_->name }
                                 $c->model('MyApp::Country')->all ],
                    other   => 1,   # create "Other:" box
                    );

This would create a select list with the last element as "Other:" to allow
the addition of more countries.

Finally, to render it in your template, you would just use render to get
a default table-based form:

    <!-- root/src/books/edit.tt -->
    [% form.render %]

You can also get fine-tuned control over your form layout from with your template.

=head1 TEMPLATES

The simplest way to get your form into HTML is to reference the
C<form.render> method, as shown above. However, frequently you
want more control.

From within your template, you can reference any of FormBuilder's 
methods to manipulate form HTML, JavaScript, and so forth. For example,
you might want exact control over fields, rendering them in a C<< <div> >>
instead of a table. You could do something like this:

    <!-- root/src/books/edit.tt -->
    <head>
      <title>[% form.title %]</title>
      [% form.jshead %]<!-- javascript -->
    </head>
    <body>
      [% form.start %]
      <div id="form">
        [% FOREACH field IN form.fields %]
        <div id="[%- field.name -%]">
          <div class="label">
            [% field.required
                  ? qq(<span class="required">$field.label</span>)
                  : field.label
            %]
          </div>
          <div class="field">
            [% field.tag %]
            [% IF field.invalid %]
                <span class="error">
                    Missing or invalid entry, please try again.
                </error>
            [% END %]
          </div>
        </div>
        [% END %]
        <div id="submit">[% form.submit %]</div>
        <div id="reset">[% form.reset %]</div>
        <div id="state">
          [% # The following two tags include state information %]
          [% form.statetags  %]
          [% form.keepextras %]
          [% form.end        %]
        </div>
      </div><!-- form -->
    </body>

In this case, you would B<not> call C<form.render>, since that would
only result in a duplicate form (once using the above expansion, and
a second time using FormBuilder's default rendering).

Note that the above form could become a generic C<form.tt> template
which you simply included in all your files, since there is nothing
specific to a given form hardcoded in (that's the idea, after all).

You can also get some ideas based on FormBuilder's native Template Toolkit
support at L<CGI::FormBuilder::Template::TT2>.

=head1 CONFIGURATION

You can set defaults for your forms using Catalyst's config method:

    MyApp->config(form => {
        method     => 'post',
        stylesheet => 1,
        messages   => '/locale/fr_FR/form_messages.txt',
    });

This accepts the exact same options as FormBuilder's C<new()> method
(which is alot). See L<CGI::FormBuilder> for a full list of options.

Two special configuration parameters control how this plugin resolves
form config files:

=over

=item form_path

The path to configuration files. This should be set to an absolute
path to prevent problems. Within this plugin, it is set to:

    form_path => File::Spec->catfile($c->config->{home}, 'root', 'forms');

This can be a colon-separated list of directories, if you want to
specify multiple paths (ie, "/templates1:/template2").

=item form_suffix

The suffix that configuration files have. By default, it is C<fb>.

=back

In addition, the following FormBuilder options are automatically set for you:

=over

=item action

This is set to the URL for the current action. B<FormBuilder> is designed
to handle a full request cycle, meaning both rendering and submission. If
you want to override this, simply use the C<< $c->form >> object:

    $c->form->action('/action/url');

The default setting is C<< $c->req->path >>.

=item debug

This is set to correspond with Catalyst's debug setting.

=item params

This is set to get parameters from Catalyst, using C<< $c->req->params >>.
To override this, use the C<< $c->form >> object:

    $c->form->params(\%param_hashref);

Overriding this is not recommended.

=item source

This determines which source file is loaded, to setup your form. By
default, this is set to the name of the action URL, with C<.fb> appended.
For example, C<edit_form()> would be associated with an C<edit_form.fb>
source file.

To override this, include the path as the argument to the method attribute:

    sub edit : Form('/books/myEditForm') { }

If no source file is found, then it is assumed you'll be setting up your
fields manually. In your controller, you will have to use the C<< $c->form >>
object to create your fields, validation, and so on.

=back

=head1 SEE ALSO

L<CGI::FormBuilder>, L<CGI::FormBuilder::Source::File>, L<CGI::FormBuilder::Template::TT2>,
L<Catalyst::Manual>, L<Catalyst::Request>, L<Catalyst::Response>

=head1 AUTHOR

Copyright (c) 2006 Nate Wiger <nate@wiger.org>. All Rights Reserved.

Thanks to Laurent Dami for many good suggestions regarding this plugin.

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

