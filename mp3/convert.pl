#!perl -w
use strict;
my $config = {
  soxBinaryPath   => 'c:/apps/sox/sox.exe',
  flacBinaryPath  => 'c:/apps/flac/flac.exe',
  lameBinaryPath  => 'c:/windows/lame.exe',
  defaultEncoding => 'insane',
  isDebug         => 1,
};

ConvertFilesToMP3->new($config)->run(@_);

package ConvertFilesToMP3;
use strict;
use warnings;
use Cwd;
use Config;
use File::Copy;

=pod

=head1 Description

This script can be used to convert media files found in a folder structure
to mp3 files, given a certain resolution/preset.

The script will attempt to preserve the ID3/ID3V2 tags if found,
or generate tags based on the folder structure (Artist/Album).

For efficient tagging, the script uses MP3::Info to read tags 
from the source files. If this package is not installed and tagging
is explicitly expected to be read from source files, the script will fail.

The script relies on a few external binaries, listed below.

=over

=item Lame MP3

This is the MP3 encoder, a command-line application. 
The latest version can be compiled from source, which can be retrieved here:

 http://lame.sourceforge.net/download.php

For Windows users, the pre-compiled binary can be downloaded from here:

 http://www.free-codecs.com/download/lame_encoder.htm

=item FLAC encoder

I<Optional>

This binary can be used to convert flac files to wav files, which 
can be then used as a source by the lame encoder to create the MP3 files.

The source code and the pre-compiled binaries for all platforms
can be downloaded here:

 http://flac.sourceforge.net/download.html

=item Sound eXchange audio editor

I<Optional>

This command-line audio editor can be used in the conversion process
to apply fade-in and fade-out for each track.

The source code and the pre-compiled binaries for all platforms
can be downloaded here:

 http://sox.sourceforge.net/

=back

=head1 Usage

You can call this script as described below. 
If there are spaces in the folder name, you need to quote the path.

 convert.pl /my/source/folder /target/folder preset=... tags=... fade=...

If you are not providing an encoding type, the script will 
use by default "lame --preset fast standard" on all the files in the path.

=head2 Parameters

=over

=item preset

This parameter takes the string to be used with the lame --preset option.
See the lame documentation for more information.

Examples of using acceptable values:

 preset=insane
 preset="fast extreme"

Bitrate overview (mostly based on LAME 3.98.2 results)  

 Switch  Preset                  Target Kbit/s  Bitrate range kbit/s  
 -b 320  --preset insane         320            320 CBR
 -V 0    --preset fast extreme   245            220...260
 -V 1                            225            190...250
 -V 2    --preset fast standard  190            170...210
 -V 3                            175            150...195
 -V 4    --preset fast medium    165            140...185
 -V 5                            130            120...150
 -V 6                            115            100...130
 -V 7                            100            80...120
 -V 8                            85             70...105
 -V 9                            65             45...85


=item tags

The "tags" parameter specifies how the ID3 tags should be built.
The script will try to use the methods in order. If the ID3 was specified 
and no ID3 was defined, the other methods will be used to define the tags. 

  tags=id3,path,name

The following tags can be used:

 id3    Use the ID3 tags if defined.
 
 path   Use the last two folders in the path to define the artist and the album name.
        The script will fail if the path is not deep enough to define both.
 
 name   Use the file name to separate the artist, album, and track name.
        The script will fail if the name of a track does not contain all required fields.

When using the "name" parameter, the file name would have to contain
the Artist, Album, and track title, separated by dashes:

 Artist - Album Name - Track Name.mp3

If a track contains the track number in the beginning, it will be used 
to set the track number field.

 01 - Artist - Album Name - Track Name.mp3


=item fade

When specified, this will rely on sox (http://sox.sourceforge.net/) to apply
fade-in and fade-out. You can specify these params as:

 fade=in:0.5,out:2.5

This will fade in for half a second, and fade out for 2.5 seconds.

The fade can be applied only to wav files.

If the source file is an mp3 file, the file will be first converted to wav,
then the fade will be applied, then the file will be converted back to mp3.

=back

B<Examples>

This will use "lame --preset cbr 160" on all the files in the path:

 convert.pl "c:/Media files/myFolder" preset="cbr 160"

You can also provide a target folder

 convert.pl "c:/Media files/myFolder" "c:/Target folder" preset="cbr 160"

If you need to fade-in/fade-out every track, you can also provide
the parameters that will be used by SOX:

 convert.pl "c:/Media files/myFolder" preset=insane fade=in:0.1,out:0.5,trim:0.2

The above command will encode in-place the source files, applying to each file
a fade-in of 0.1s, a fade-out of 0.5s and trimming the last 0.2s away 
from the end of the file.


=cut
sub new {
  my $package = shift;
  my $self    = shift;
  my $os = $^O || $Config::Config{'osname'};
  $self->{isDebug}           ||= 0;
  $self->{lameBinaryPath}    ||= 'c:/apps/lame/lame.exe';
  $self->{flacBinaryPath}    ||= 'c:/apps/flac/flac.exe';
  $self->{defaultEncoding}   ||= 'insane';
  # How many folders deep to go look for files
  $self->{maxNestingLevel}   ||= 10;
  # Output files smaller than 10K might be the result of an encoding error.
  $self->{minFileSize}       = 10000;
  $self->{defaultLameParams} = [
    '--quiet',
    '--add-id3v2',
  ];
  $self->{isWin32}  = $os =~ /win/ ? 1 : 0;
  return bless $self, $package;
}

sub run {
  my $self        = shift;
  my $sourcePath  = shift || $self->end("No source path provided");
  my $targetPath  = shift || '';
  my @otherParams = @_;
  $|++;
  my $defaultEncoding   = $self->{defaultEncoding};
  my $lameBinaryPath    = $self->{lameBinaryPath};
  my $flacBinaryPath    = $self->{flacBinaryPath};
  my $minFileSize       = $self->{minFileSize};
  my $maxNestingLevel   = $self->{maxNestingLevel};
  my $defaultLameParams = $self->{defaultLameParams};
  my $isDebug           = $self->{isDebug};
  
  if ($targetPath =~ /=/) {
    unshift @otherParams, $targetPath;
    $targetPath = $sourcePath;
  }
  my $inParams   = join ' ', @otherParams;
  
  my (@messages, @errors);
  my $opParams  = $self->{opParams} = {};
  my @outParams = @$defaultLameParams;
  my @buildTags = ('id3');
  
  $sourcePath = $self->makeAbsolutePath($sourcePath);
  $targetPath = $self->makeAbsolutePath($targetPath);
  $self->end("Invalid path provided: $sourcePath")
   if ! -e $sourcePath
   || ! -d $sourcePath;
  
  if (! -e $targetPath) {
    mkdir($targetPath, 0777)
      || $self->end("Could not create path($targetPath):".$!);
  }
  
  if ($inParams =~ /preset=(".+?"|\S+)/) {
    my $preset = $1;
    $preset    = $1 if $preset =~ /^"(.+)"$/;
    push @outParams, '--preset '.$preset;
  }
  else {
    push @messages, qq~You did not provide an encoding standard, using "$defaultEncoding".~;
    push @outParams, '--preset '.$defaultEncoding;
  }
  
  if ($inParams =~ /tags=(\S+)/) {
    @buildTags = split ',', lc $1;
    foreach(@buildTags) {
      $_ =~ s/^\s+//;
      $_ =~ s/\s+$//;
      $self->end("Invalid tag param: ".$_)
        if $_ !~ /^(id3|name|path)/o;
    }
    push @messages, "The tags will be built from: ".(join ', then ', @buildTags);
  }
  
  if ($inParams =~ /fade=(\S+)/) {
    # fade=in:0.5,out:2.5
    my %fade;
    my @fadeParams = split /,/, $1;
    map {$fade{lc $1} = $2 if $_ =~ /(in|out)=(\d+|\d*\.\d+)/i} @fadeParams;
    $self->{fadeParams} = \%fade if %fade;
  }
  
  push @messages, 'The new files will be created in: '.$targetPath
    if $sourcePath ne $targetPath;
  
  my $lameParams = join ' ', @outParams;
  my $fadeMessage = $self->{fadeParams}
    ? "Fade params were specified, and can only applied to wav files.
If the source files are mp3, the fade params will be ignored."
    : '';
  print ''.("=" x 60)."\n"
    .(join "\n\n", @messages)
    .qq~\n\nThe files in the following path:\n\n\t$sourcePath\n
will be converted using the following lame params:

\t$lameBinaryPath $lameParams

$fadeMessage
You have 5 seconds to stop this...\n~;
  sleep 5;
  
  $opParams->{-LAME_PARAMS} = $lameParams;
  $opParams->{-BUILD_TAGS}  = \@buildTags;
  
  $self->workDir($sourcePath, $targetPath);
  $self->printMessages();
  return;
}

sub makeAbsolutePath {
  my $self = shift;
  my $path = shift;
  # If we are processing files in the current path,
  # we should make it an absolute path for lame.
  # We will also convert windows-style paths to Perl-style paths.
  if ($path eq '.') {
    $path = getcwd();
  }
  elsif ($path !~ /^(\w\:|\/)/) {
    $path = getcwd().'/'.$path;
  }
  $path =~ s/\\/\//g if $path =~ /\\/;
  return $path;
}

sub addError {
  my $self     = shift;
  my $message  = shift;
  my $messages = $self->{opParams}{-ERRORS} ||= [];
  push @$messages, $message;
  return;
}

sub addMessage {
  my $self     = shift;
  my $message  = shift;
  my $messages = $self->{opParams}{-MESSAGES} ||= [];
  push @$messages, $message;
  return;
}

sub printMessages {
  my $self     = shift;
  my $messages = $self->{opParams}{-MESSAGES} ||= [];
  my $errors   = $self->{opParams}{-ERRORS}   ||= [];
  if (@$messages) {
    print ''.("=" x 60)."\n";
    print "PROCESS RESULTS:\n".(join "\n", @$messages)."\n";
  }
  if (@$errors) {
    print ''.("=" x 60)."\n";
    print "ERRORS found:\n".(join "\n", @$errors)."\n";
  }
  else {
    print "OK\n";
  }
  return;
}

sub workDir {
  my $self        = shift;
  my $currentPath = shift;
  my $targetPath  = shift;
  my $level       = shift || 1;
  
  my $flacBinaryPath  = $self->{flacBinaryPath};
  my $soxBinaryPath   = $self->{soxBinaryPath};
  my $maxNestingLevel = $self->{maxNestingLevel};
  my $minFileSize     = $self->{minFileSize};
  my $fadeParams      = $self->{fadeParams};
  if ($fadeParams) {
    $self->quit("No soxBinaryPath defined")
      if ! $soxBinaryPath;
    $self->quit("The soxBinaryPath is not valid: $soxBinaryPath")
      if ! -e $soxBinaryPath;
  }
  return if $maxNestingLevel < $level;
  if (! -e $targetPath) {
    mkdir($targetPath, 0777)
      || $self->end("Could not create path($targetPath):".$!);
  }
  my $isProcessInPlace = $currentPath eq $targetPath ? 1 : 0;
  
  my ($dh, @errors, @messages);
  my $opParams   = $self->{opParams};
  my $buildTags  = $opParams->{-BUILD_TAGS};
  my $lameParams = $opParams->{-LAME_PARAMS};
  
  if (! opendir ($dh, $currentPath)) {
    $self->addError($currentPath);
    $self->addError("Can't open $currentPath:. ".$!);
    return;
  }
  my @files = sort grep(!/^\.\.?$/, readdir($dh));
  closedir ($dh);
  
  print "PATH: $currentPath\n";
  
  foreach my $fileName(@files) {
    my $sourceFile = "$currentPath/$fileName";
    if (-d $sourceFile) {
      my $newTargetPath = "$targetPath/$fileName";
      if (! -e $newTargetPath) {
        mkdir($newTargetPath, 0777)
          || $self->end("Could not create path($newTargetPath):".$!);
      }
      $self->workDir($sourceFile, $newTargetPath, $level + 1); 
      next;
    };
    if ($fileName =~ /(.+)\.mp3$/oi) {
      my $targetFile = $isProcessInPlace
        ? "$currentPath/temp.mp3"
        : "$targetPath/$fileName";
      
      unlink $targetFile
        if $isProcessInPlace && -e $targetFile;
      
      print "CONVERT: $fileName\n";
      
      my $message = $self->encodeFile($sourceFile, $targetFile, $lameParams, $buildTags);
      if ($message) {
        push @messages, $fileName;
        push @messages, @$message;
      }
      if (! -e $targetFile) {
        push @errors, $fileName;
        push @errors, "Encode failed, mp3 target file could not be created";
      }
      elsif (-s $targetFile < $minFileSize) {
        push @errors, $fileName;
        push @errors, "Encode failed, output smaller than "
          .(sprintf "%.2d", $minFileSize / 1000)
          ."KB, keeping original file.";
        unlink $targetFile;
        copy($sourceFile, $targetFile) if ! $isProcessInPlace;
      }
      else {
        if ($isProcessInPlace) {
          unlink $sourceFile;
          rename ($targetFile, $sourceFile)
            || $self->end("could not rename $targetFile to $sourceFile");
        }
      }
    }
    elsif ($fileName =~ /(.+)\.(wav|flac)$/oi) {
      my $fRoot = $1;
      my $targetFileWav;
      if ($fileName =~ /\.flac$/oi) {
        print "CONVERT: $fileName to wav\n";
        $fileName      = "$fRoot.wav";
        $targetFileWav = "$currentPath/$fileName";
        unlink $targetFileWav
          if $isProcessInPlace && -e $targetFileWav;
        
        `$flacBinaryPath -d "$sourceFile" -o "$targetFileWav"`;
        
        my $oldFile = $sourceFile;
        $sourceFile = "$currentPath/$fileName";
        unlink $oldFile
          if $isProcessInPlace && -e $sourceFile;
      }
      my $targetFile = "$targetPath/$fRoot.mp3";
      unlink $targetFile
        if $isProcessInPlace && -e $targetFile;
      
      print "CONVERT: $fileName\n";
      
      my $tempTargetFile;
      if ($fadeParams) {
        my $trim    = $fadeParams->{trim} || '';
        my $fadeIn  = $fadeParams->{in}   || 0;
        my $fadeOut = $fadeParams->{out}  || 0;
        if ($trim || $fadeIn || $fadeOut) {
          $tempTargetFile = "$targetPath/$fRoot.fade.wav";
          my $thisFadeParams;
          $thisFadeParams   .= "$fadeIn 0 $fadeOut"
            if $fadeIn || $fadeOut;
          $thisFadeParams   .= " trim =0 -$trim" if $trim;
          
          print "FADE: $thisFadeParams\n";
          
          `$soxBinaryPath "$sourceFile" "$tempTargetFile" $thisFadeParams`;
          
          $sourceFile = $tempTargetFile;
        }
      }
      my $message = $self->encodeFile($sourceFile, $targetFile, $lameParams, $buildTags);
      
      unlink $targetFileWav  if $targetFileWav;
      unlink $tempTargetFile if $tempTargetFile;
      
      if ($message) {
        push @messages, $fileName;
        push @messages, @$message;
      }
      if (! -e $targetFile) {
        push @errors, $fileName;
        push @errors, "\tEncode failed, see log";
      }
    }
    else {
      print "SKIP: $fileName\n";
    }
  }
  if (@errors) {
    $self->addError($currentPath);
    map { $self->addError("  $_") } @errors;
  }
  if (@messages) {
    $self->addMessage($currentPath);
    map { $self->addMessage("  $_") } @messages;
  }
  return;
}

sub end {
  my $self    = shift;
  my $message = shift;
  print "$message\n";
  exit 1;
}

sub getTagsFromID3 {
  my $self       = shift;
  my $sourceFile = shift;
  my $messages   = shift;
  if ($sourceFile !~ /\.mp3$/oi) {
    push @$messages, '=I= Source not an MP3 file, cannot read ID3 tags';
    return {};
  }
  eval 'use MP3::Info;';
  if ($@) {
    push @$messages, '=I= Could not load MP3::Info: '.$@;
    return {};
  }
  # This method is exported by MP3::Info
  my $tagFromID3 = get_mp3tag($sourceFile) || {};
  if (! keys %$tagFromID3) {
    push @$messages, '=I= MP3 file with no ID3 tags';
  }
  else {
    push @$messages, '=I= MP3 file has ID3 tags';
  }
  return $tagFromID3;
}

sub getTagsFromPath {
  my $self       = shift;
  my $sourceFile = shift;
  my $messages   = shift;
  my %tagFromPath;
  if ($sourceFile =~ /([^\/]+)\/([^\/]+)\/(\d+)\s*-\s*([^\/]+)\.w+$/o) {
    push @$messages, '=P= Simple file name, extracting Artist/Album from path.';
    $tagFromPath{ARTIST}   = $1;
    $tagFromPath{ALBUM}    = $2;
    $tagFromPath{TRACKNUM} = $3;
    $tagFromPath{TITLE}    = $4;
  }
  elsif ($sourceFile =~ /(?:Various Artists|V\.A\.?)\/([^\/]+)\/(\d+)\s*(\.|-)\s*([^\/]+)\.w+$/oi) {
    $tagFromPath{ALBUM}    = $1;
    $tagFromPath{TRACKNUM} = $2;
    my $title              = $3;
    $tagFromPath{ARTIST}   = 'Various Artists';
    $tagFromPath{TITLE}    = $title;
    if ($title =~ /([^.]+)\s+\.\s+(.+)/o ||
        $title =~ /([^\-]+)\s+-\s+(.+)/o) {
      $tagFromPath{ARTIST} = $1;
      $tagFromPath{TITLE}  = $2;
      push @$messages, '=P= Extract artist name from file name';
    }
    else {
      push @$messages, '=P= No artist name could be determined from path or file name';
    }
  }
  return \%tagFromPath;
}

sub getTagsFromName {
  my $self       = shift;
  my $sourceFile = shift;
  my $messages   = shift;
  return if $sourceFile !~ /([^\/\\]+)\.\w+$/oi;
  my %tagFromName;
  
  my $fileName = $1;
  if ($fileName =~ /^\(([^(]*)\)(.+)/o ||
      $fileName =~ /^\[([^\]]*)\](.+)/) {
    $tagFromName{ALBUM} = $1;
    $fileName           = $2;
    push @$messages, "=N= Album name: $1";
  }
  if ($fileName =~ /(.+)\((\d\d\d\d)\)$/o) {
    $tagFromName{YEAR} = $2;
    $fileName          = $1;
    push @$messages, "=N= Album year: $2";
  }
  
  my @fileName = map {
    $_ =~ s/_/ /g;
    $_ =~ s/\s+/ /g;
    $_ =~ s/^\s+//;
    $_ =~ s/\s+$//;
    $_
  } split /-/, $fileName;
  
  shift @fileName until $fileName[0] ne '' || ! @fileName;
  return \%tagFromName if ! @fileName;
  
  push @$messages, "=N= Using for tagging:\n\t".(join "|", @fileName);
  
  if ($fileName[0] =~ /^\d+$/) {
    $tagFromName{TRACKNUM} = shift @fileName;
  }
  if (2 < @fileName) {
    if (! exists $tagFromName{ALBUM}) {
      $tagFromName{ALBUM}  = shift @fileName;
    }
    $tagFromName{ARTIST} = shift @fileName;
    $tagFromName{TITLE}  = join '-', @fileName;
  }
  elsif (@fileName == 2) {
    $tagFromName{ARTIST} = shift @fileName;
    $tagFromName{TITLE}  = shift @fileName;
  }
  else {
    $tagFromName{TITLE}  = shift @fileName;
  }
  return \%tagFromName;
}


sub encodeFile {
  my ($x, %tag, $tagSource);
  my $self       = shift;
  my $sourceFile = shift;
  my $targetFile = shift;
  my $lameParams = shift;
  my $buildTags  = shift;
  my @messages;
  my $lameBinaryPath = $self->{lameBinaryPath};
  # These are the params as defined by the MP3::Info
  my @mp3Params  = qw(TITLE YEAR ARTIST ALBUM GENRE TRACKNUM COMMENT);
  my %defaultTag = (
    TITLE    => '',
    YEAR     => '',
    ARTIST   => '',
    ALBUM    => '',
    GENRE    => 'Rock',
    TRACKNUM => '',
    COMMENT  => '',
  );
  my %buildTags = map { $_ => 1 } @$buildTags;
  
  my $tagFromID3  = $buildTags{'id3'}
    ? $self->getTagsFromID3($sourceFile, \@messages)  || {}
    : {};
  my $tagFromPath = $buildTags{'path'}
    ? $self->getTagsFromPath($sourceFile, \@messages) || {}
    : {};
  my $tagFromName = $buildTags{'name'}
    ? $self->getTagsFromName($sourceFile, \@messages) || {}
    : {};
  
  foreach $x(@mp3Params) {
    foreach $tagSource(@$buildTags) {
      # Once defined, a tag cannot be overriden
      next if exists $tag{$x} && defined $tag{$x} && $tag{$x} ne '';
      
      if ($tagSource eq 'path') {
        $tag{$x} = $tagFromPath->{$x} if exists $tagFromPath->{$x} && defined $tagFromPath->{$x};
      }
      elsif ($tagSource eq 'id3') {
        $tag{$x} = $tagFromID3->{$x} if exists $tagFromID3->{$x} && defined $tagFromID3->{$x};
      }
      elsif ($tagSource eq 'name') {
        $tag{$x} = $tagFromName->{$x} if exists $tagFromName->{$x} && defined $tagFromName->{$x};
      }
      $tag{$x} = $defaultTag{$x} if ! exists $tag{$x} || ! defined $tag{$x} || $tag{$x} eq '';
      $tag{$x} =~ s/\s+$//;
      $tag{$x} =~ s/\s+/ /;
      $tag{$x} =~ s/^\s+//;
      $tag{$x} =~ s/\s+$//;
      $tag{$x} =~ s/^\((.*)\)$/$1/;
      $tag{$x} =~ s/^\[(.*)\]$/$1/;
      $tag{$x} =~ s/^\s+//;
      $tag{$x} =~ s/\s+$//;
      $tag{$x} =~ s/[|\\\/]/~/g; # use "~" instead of one of the following: | / \
      $tag{$x} =~ s/"/'/g; # use ' instead of "
      push @messages, "=== $x($tagSource)=$tag{$x}" if $tag{$x} ne '';
    }
  }
  $tag{'TRACKNUM'} = $1
    if $tag{'TRACKNUM'} =~ /(\d+)\D/;
  
  $lameParams .= qq~ --tt "$tag{'TITLE'}"~    if $tag{'TITLE'}    ne '';
  $lameParams .= qq~ --ty "$tag{'YEAR'}"~     if $tag{'YEAR'}     ne '';
  $lameParams .= qq~ --ta "$tag{'ARTIST'}"~   if $tag{'ARTIST'}   ne '';
  $lameParams .= qq~ --tl "$tag{'ALBUM'}"~    if $tag{'ALBUM'}    ne '';
  $lameParams .= qq~ --tg "$tag{'GENRE'}"~    if $tag{'GENRE'}    ne '';
  $lameParams .= qq~ --tn "$tag{'TRACKNUM'}"~ if $tag{'TRACKNUM'} ne '';
  $lameParams .= qq~ --tc "$tag{'COMMENT'}"~  if $tag{'COMMENT'}  ne '';
  
  if ($self->{isWin32}) {
    $sourceFile =~ s/\//\\/g;
    $targetFile =~ s/\//\\/g;
  }
  my $sourceSize = -s $sourceFile;
  my $cmd = qq~$lameBinaryPath $lameParams "$sourceFile" "$targetFile"~;
  push @messages, "=== RUN: $cmd";
  `$cmd`;
  my $targetSize = -e $targetFile ? -s $targetFile : 0;
  if ($sourceSize && $targetSize) {
    push @messages, "Size changed from "
      .(sprintf '%.2d', $sourceSize / 1000)."K to "
      .(sprintf '%.2d', $targetSize / 1000)."K.";
  }
  else {
    push @messages, 'ERROR:Could not convert';
  }
  push @messages, ("=" x 40);
  
  @messages = () if ! $self->{isDebug};
  
  return \@messages;
}