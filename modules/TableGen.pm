## @file
# This file contains the implementation of the table generator library
#
# @author  Chris Page &lt;chris@starforge.co.uk&gt;
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

## @class
#
package TableGen;

use v5.12;
use base qw(Webperl::SystemModule);
use Webperl::Utils qw(path_join);
use XML::Simple;

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Construct a new TableGen model object to handle loading of year
# data and lookup of week information.
#
# @param args A hash of values to initialise the object with.
# @return A new TableGen object.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(minimal => 1, # minimal tells SystemModule to skip object checks
                                        course  => '',
                                        basedir => '',
                                        formats => { "weekdate"   => "%d %b",
                                                     "weekdaymon" => "%a %d %b",
                                                     "weekday"    => "%a %d",
                                        },
                                        @_)
        or return undef;

    # must have academic year and template objects
    return Webperl::SystemModule::set_error("No Template object available.") if(!$self -> {"template"});
    return Webperl::SystemModule::set_error("No AcademicYear object available.") if(!$self -> {"acyear"});

    # If a course has been set, tryo to load it
    $self -> load_course() or return Webperl::SystemModule::set_error($self -> errstr())
        if($self -> {"course"});

    return $self;
}

# ============================================================================
#  Course loader and access

## @method $ load_course($course)
# Load the table and link definitions for the specified course.
#
# @param course The name of the course to load the definitions for. If not
#               set, the course specified when creating the object is used.
# @return true on success, undef on error.
sub load_course {
    my $self   = shift;
    my $course = shift || $self -> {"course"}; # default to the initial course if not set

    $self -> clear_error();

    return $self -> self_error("No course specified")
        if(!$course);

    # Read the table and link definitions into a hash
    my $definitions = { };
    $definitions -> {"table"} = $self -> _load_table_data($course)
        or return undef;

    $definitions -> {"links"} = $self -> _load_link_data($course)
        or return undef;

    # reading was successful, so store the filename and data
    $self -> {"course"}    = $course;
    $self -> {"coursedef"} = $definitions;

    return 1;
}


## @method $ generate($year)
# Generate a table for the specified year using the current course definitions.
#
# @param year The Id of the year to generate the table for.
# @return A string containing the table on success, undef on error.
sub generate {
    my $self = shift;
    my $year = shift;

    $self -> clear_error();

    # Can't do anything if the content isn't loaded
    return $self -> self_error("No course definition information loaded")
        if(!$self -> {"coursedef"});

    # Build the week data for the current year
    my $weeks = [ $self -> {"acyear"} -> weeks(year => $year, semester => "1", initial_welcome => 1),
                  $self -> {"acyear"} -> weeks(year => $year, semester => "2") ];

    # Construct the values inside the table
    my $header = $self -> _build_header($self -> {"coursedef"} -> {"table"} -> {"columns"} -> {"column"});
    my $body   = $self -> _build_body($self -> {"coursedef"} -> {"table"} -> {"columns"} -> {"column"},
                                      $self -> {"coursedef"} -> {"table"} -> {"rows"} -> {"row"},
                                      $self -> {"coursedef"} -> {"table"} -> {"rows"} -> {"rowhash"},
                                      $weeks);

    # work out whether the table needs a class definition set
    my $class = "";
    $class = $self -> {"template"} -> load_template("class.tem", {"***class***" => $self -> {"coursedef"} -> {"table"} -> {"columns"} -> {"class"}})
        if($self -> {"coursedef"} -> {"table"} -> {"columns"} -> {"class"});

    # Build the table and the html page to contain it.
    my $table = $self -> {"template"} -> load_template("table.tem", {"***class***"  => $class,
                                                                     "***header***" => $header,
                                                                     "***rows***"   => $body});

    return $self -> {"template"} -> load_template("container.tem", {"***course***" => $self -> {"course"},
                                                                    "***style***"  => $self -> {"coursedef"} -> {"table"} -> {"style"},
                                                                    "***table***"  => $table});
}

# ============================================================================
#  Internal implementation

## @method private $ _load_link_data($course)
# Load the link definitions from the links.xml file associated with the specified
# course.
#
# @param course The name of the course to load the data for
# @return A reference to a hash containing the link data on success, undef on error.
sub _load_link_data {
    my $self   = shift;
    my $course = shift;

    $self -> clear_error();

    # load and parse the xml link file. the XMLin settings are slightly
    # voodoo: they ensure that links are stored as <id> => <url> associations,
    # rather than <id> => { "content" => <url> }.
    my $linkfile = path_join($self -> {"basedir"}, "courses", $course, "links.xml");
    my $linkdata = eval { XMLin($linkfile, KeepRoot => 0, ContentKey => '-content', KeyAttr => [ 'name' ]) };
    return $self -> self_error("Link file loading failed for $course: $@")
        if($@);

    return $linkdata;
}


## @method private $ _load_table_data($course)
# Load the table definition from the table.xml file associated with the specified
# course.
#
# @param course The name of the course to load the data for
# @return A reference to a hash containing the table definition on success, undef
#         on error.
sub _load_table_data {
    my $self   = shift;
    my $course = shift;

    $self -> clear_error();

    # Load the table definition xml file. Again, the XMLin settings are a bit voodoo,
    # and they should be left alone unless you know what you're doing.
    my $tablefile = path_join($self -> {"basedir"}, "courses", $course, "table.xml");
    my $tabledata = eval { XMLin($tablefile, KeepRoot => 0, ForceArray => [ 'column', 'data' ], KeyAttr => { 'column' => '', data => 'for' }) };
    return $self -> self_error("Table definition loading failed for $course: $@")
        if($@);

    # The $tabledata -> {"rows"} -> {"row"} value is an arrayref, there may need
    # to be a lookup table too, so construct one
    foreach my $row (@{$tabledata -> {"rows"} -> {"row"}}) {
        my $id = defined($row -> {"week"}) ? $row -> {"week"} : $row -> {"break"};
        push(@{$tabledata -> {"rows"} -> {"rowhash"} -> {$row -> {"semester"}} -> {$id}}, $row);
    }

    return $tabledata;
}


## @method private $ _build_header($columns)
# Generate a table header row using the specified column data to
# define the values in the header cells.
#
# @param columns A reference to an array of header columns.
# @return A string containing the header row.
sub _build_header {
    my $self    = shift;
    my $columns = shift;
    my $header  = "";

    # Generate the contents of the header cells.
    foreach my $col (@{$columns}) {
        my $class = "";

        $self -> {"template"} -> load_template("class.tem", "***class***" => $col -> {"class"})
            if($col -> {"class"});

        $header .= $self -> {"template"} -> load_template("header.tem", {"***class***" => $class,
                                                                         "***text***"  => $col -> {"title"}});
    }

    # Wrap the line in a row if there is any content
    $header = $self -> {"template"} -> load_template("row.tem", {"***class***" => '',
                                                                 "***cols***"  => $header})
        if($header);

    return $header;
}


## @method private $ _build_body($columns, $rows)
# Generate the table body using the specified column and row data.
#
# @param columns A reference to an array of header columns.
# @param rows    A reference to an array of row hashes.
# @param weeks   A reference to an array of week definitions.
# @return A string containing the header row.
sub _build_body {
    my $self    = shift;
    my $columns = shift;
    my $rows    = shift;
    my $rowhash = shift;
    my $weeks   = shift;
    my $body    = "";

    # Precalulate the number of columns to save a bit of time later
    my $colcount = scalar(@{$columns});
    my $break = "";
    foreach my $semester (@{$weeks}) {
        foreach my $week (@{$semester -> {"calendar"}}) {
            my $weekdata = $semester -> {$week -> {"type"}} -> {$week -> {"id"}};

            # Handle skipping of multi-week breaks
            if($week -> {"type"} eq "break") {
                next if($break && $break eq $week -> {"id"});

                $break = $week -> {"id"};
            } else {
                $break = "";
            }

            # Got a semester and week number, fetch the defined value for that
            my $rows = $rowhash -> {$weekdata -> {"semester"}} -> {$week -> {"id"}};
            next unless($rows);

            foreach my $rowdata (@{$rows}) {
                my $row = "";
                my $rowvalues = $self -> _generate_template_vars($weekdata);

                # allow rows to mark themselves as headers
                my $mode = $rowdata -> {"header"} ? "header.tem" : "cell.tem";

                for(my $colnum = 0; $colnum < $colcount; ++$colnum) {
                    # Pull out some values to help with readability
                    my $column = $columns -> [$colnum];
                    my $data   = $rowdata -> {"data"} -> {$column -> {"id"}};
                    my ($span, $class) = ("", "");

                    if($data -> {"span"}) {
                        $span = $self -> {"template"} -> load_template("colspan.tem", {"***span***" => $data -> {"span"}});
                        $colnum += ($data -> {"span"} - 1); # Skip columns to match the span
                    }

                    $class = $self -> {"template"} -> load_template("class.tem", {"***class***" => $data -> {"class"}})
                        if($data -> {"class"});

                    # Set the values to substitute
                    $rowvalues -> {"***text***"}  = $data -> {"content"};
                    $rowvalues -> {"***span***"}  = $span;
                    $rowvalues -> {"***class***"} = $class;

                    $row .= $self -> {"template"} -> load_template($mode, $rowvalues);
                }

                # Wrap the row up in a row template if needed
                if($row) {
                    my $rowclass = "";
                    $rowclass = $self -> {"template"} -> load_template("class.tem", {"***class***" => $rowdata -> {"class"}})
                        if($rowdata -> {"class"});

                    $body .= $self -> {"template"} -> load_template("row.tem", {"***class***" => $rowclass,
                                                                                "***cols***"  => $row});
                }
            }
        }
    }

    return $body;
}


## @method private $ _generate_template_vars($week)
# Generate a hash containing template replacement values to use in
# row building.
#
# @param week A reference to the week data
# @return A reference to a hash containing template replacement values.
sub _generate_template_vars {
    my $self     = shift;
    my $week     = shift;

    my $output = { "{T_[weeknum]}"  => $week -> {"id"},
                   "{T_[semester]}" => $week -> {"semester"} };

    # Add links
    if($self -> {"coursedef"} -> {"links"} -> {"link"}) {
        foreach my $file (keys(%{$self -> {"coursedef"} -> {"links"} -> {"link"}})) {
            my $content = $self -> {"coursedef"} -> {"links"} -> {"link"} -> {$file};

            # Handle situations where XML::Simple has used a content key, despite being told not to
            $content = $content -> {"content"} if(ref($content) eq "HASH");

            $output -> {"{L_[$file]}"} = $content;
        }
    }

    my $date = $week -> {"date"} -> clone();;
    for(my $i = 0; $i < 7; ++$i, $date -> add(days => 1)) {
        my $ext = $i ? "+$i" : "";

        $output -> {"{T_[weekdate$ext]}"}   = $date -> strftime($self -> {"formats"} -> {"weekdate"});
        $output -> {"{T_[weekday$ext]}"}    = $date -> strftime($self -> {"formats"} -> {"weekday"});
        $output -> {"{T_[weekdaymon$ext]}"} = $date -> strftime($self -> {"formats"} -> {"weekdaymon"});
    }

    if($week -> {"break"}) {
        my $break = $week -> {"break"};

        $output -> {"{T_[breakname]}"}    = $break -> {"name"};
        $output -> {"{T_[breaksdate]}"}   = $break -> {"start"} -> strftime($self -> {"formats"} -> {"weekdate"});
        $output -> {"{T_[breaksday]}"}    = $break -> {"start"} -> strftime($self -> {"formats"} -> {"weekday"});
        $output -> {"{T_[breaksdaymon]}"} = $break -> {"start"} -> strftime($self -> {"formats"} -> {"weekdaymon"});
        $output -> {"{T_[breakedate]}"}   = $break -> {"end"} -> strftime($self -> {"formats"} -> {"weekdate"});
        $output -> {"{T_[breakeday]}"}    = $break -> {"end"} -> strftime($self -> {"formats"} -> {"weekday"});
        $output -> {"{T_[breakedaymon]}"} = $break -> {"end"} -> strftime($self -> {"formats"} -> {"weekdaymon"});
    }

    return $output;
}

1;