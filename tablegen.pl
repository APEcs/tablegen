#!/usr/bin/perl

## @file
# This file contains the course timeline table generator script.
#
# This script uses the table and link definition files for a given course
# to generate a course timeline table (showing what happens in each week,
# with links to supporting content as needed).
#
# To generate a table for a course, run this script with the course code
# and academic year:
#
# ./tablegen.pl -c comp37111 -y AY1415
#
# This will print a HTML page containing the course timeline table to
# stdout.
#
# To obtain a list of known courses and supported academic years, supply
# the -l option on the command line:
#
# ./tablegen.pl -l
#
# If -l is set, the script will print the available courses and years,
# and exit.
#
# @author  Chris Page &lt;chris@starforge.co.uk&gt;

use utf8;
use v5.12;
use FindBin;

# Work out where the script is, so module and resource loading can work.
my $scriptpath;
BEGIN {
    # This handles tainting, horribly permissively
    if($FindBin::Bin =~ /^(.*)$/) {
        $scriptpath = $1;
    }
}

# Add the support modules to the load path
use lib "$scriptpath/webperl";
use lib "$scriptpath/modules";

# Custom modules to support generation
use AcademicYear;
use TableGen;
use Webperl::Template;
use Webperl::Utils qw(path_join save_file);

# Standard perl modules
use Getopt::Long;
use Pod::Usage;

# ============================================================================
#  Support functions

## @fn void list_courses($acyear)
# Print a list of available courses to stdout and then exit.
#
# @param acyear A reference to an AcademicYear object.
sub list_courses {
    my $acyear = shift;

    opendir(COURSES, path_join($scriptpath, "courses"))
        or die "Unable to open courses directory '".path_join($scriptpath, "courses")."': $!\n";
    my @entries = readdir(COURSES);
    closedir(COURSES);

    print "Available courses:\n";
    foreach my $course (@entries) {
        next if($course =~ /^\./); # ignore dotfiles.
        print "\t$course\n";
    }

    print "\nAvailable years:\n";
    my $years = $acyear -> available_years();
    foreach my $year (@{$years}) {
        print "\t$year\n";
    }

    exit;
}


# ============================================================================
#  The code that actually Does Stuff.

# default setup variables
my $course  = ''; # which course is the user interested in?
my $year    = ''; # which year should the timetable be generated for?
my $list    = 0;  # Show a list of courses and years?
my $outfile = ''; # write the output to a file?
my $help    = 0;  # Show the help documentation
my $man     = 0;  # Print the full man page

# Parse the command line options
GetOptions('c|course:s' => \$course,
           'y|year=s'   => \$year,
           'l|list!'    => \$list,
           'o|output:s' => \$outfile,
           'h|help|?'   => \$help,
           'm|man'      => \$man)
    or pod2usage(2);
pod2usage(-verbose => 1) if($help || ((!$course || !$year) && !$list && !$man));
pod2usage(-exitstatus => 0, -verbose => 2) if($man);

# Build the objects needed to generate tables

# AcademicYear handles all things related to years, semesters, and weeks.
my $acyear = AcademicYear -> new(yearfile => path_join($scriptpath, "config", "years.xml"))
    or die "Initialisation error: ".$Webperl::SystemModule::errstr."\n";

# Template handle loading and processing of template files
my $template = Webperl::Template -> new(basedir => path_join($scriptpath, "templates"),
                                        langdir => '');

# TableGen does the actual table generation work
my $tablegen = TableGen -> new(acyear   => $acyear,
                               template => $template,
                               basedir  => $scriptpath);

# Handle listing if requested (this will not return)
list_courses($acyear) if($list);

# Explicitly load the course, rather than relying on TableGen's constructor
# to ensure that errors are caught properly.
$tablegen -> load_course($course)
    or die "Unable to load course '$course': ".$tablegen -> errstr()."\n";

# Build the table page.
my $table = $tablegen -> generate($year);

# If the user has specified an output file, use that rather
# than printing to stdout.
if($outfile) {
    save_file($outfile, $table);
} else {
    binmode STDOUT,":utf8";
    print $table;
}

__END__

=head1 NAME

tablegen.pl - Generate course timeline tables

=head1 SYNOPSIS

tablegen.pl [options]

 Options:
    -h, -?, --help  Show a brief help message.
    -m, --man       Show full documentation.
    -c, --course    The ID of the course to generate a table for.
    -y, --year      The academic year to generate the table for.
    -o, --output    The name of the file to write the table to (if not set,
                    the table is written to sdtout)
    -l, --list      List the available courses, and exit.

=head1 OPTIONS


=cut
