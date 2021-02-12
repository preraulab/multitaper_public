function [mt_spectrogram,stimes,sfreqs] = multitaper_spectrogram_mex(varargin)
%MULTITAPER_SPECTROGRAM  Compute the multitaper spectrogram for time series data
%
%   Usage:
%   Direct input:
%   [spect,stimes,sfreqs] = multitaper_spectrogram_mex(data, Fs, frequency_range, taper_params, window_params, min_NFFT, detrend_opt, plot_on, verbose)
%
%   Input:
%   data: 1 x <number of samples> vector - time series data-- required
%   Fs: double - sampling frequency in Hz  -- required
%   frequency_range: 1x2 vector - [<min frequency>, <max frequency>] (default: [0 nyquist])
%   taper_params: 1x2 vector - [<time-halfbandwidth product>, <number of tapers>] (default: [5 9])
%   window_params: 1x2 vector - [window size (seconds), step size (seconds)] (default: [5 1])
%   detrend_opt: string - detrend data window ('linear' (default), 'constant', 'off');
%   min_NFFT: double - minimum allowable NFFT size, adds zero padding for interpolation (closest 2^x) (default: 0)
%   plot_on: boolean to plot results (default: true)
%   verbose: boolean to display spectrogram properties (default: true)
%
%   Output:
%   spect: TxF matrix of spectral power
%   stimes: 1XT vector of times for the center of the spectral bins
%   sfreqs: 1XF vector of frequency bins for the spectrogram
%
%   Example:
%      Fs=200; %Sampling Frequency
%      frequency_range=[0 25]; %Limit frequencies from .5 to 25 Hz
%      taper_params=[3 5]; %Time bandwidth and number of tapers
%      window_params=[4 1]; %Window size is 4s with step size of 1s
%
%      %Generate sample chirp data
%      t=1/Fs:1/Fs:600; %Create 10 minutes of data
%      f_start=1;f_end=20; % Set chirp range in Hz
%      data=chirp(t,f_start,t(end),f_end,'logarithmic');
%
%      %Compute the multitaper spectrogram
%      [spect,stimes,sfreqs] = multitaper_spectrogram_mex(data,Fs,frequency_range, taper_params, window_params);
%
%   This code is companion to the paper:
%         "Sleep Neurophysiological Dynamics Through the Lens of Multitaper Spectral Analysis"
%         Michael J. Prerau, Ritchie E. Brown, Matt T. Bianchi, Jeffrey M. Ellenbogen, Patrick L. Purdon
%         December 7, 2016 : 60-92
%         DOI: 10.1152/physiol.00062.2015
%   which should be cited for academic use of this code.
%
%   A full tutorial on the multitaper spectrogram can be found at:
%   http://www.sleepEEG.org/multitaper
%
%   Copyright 2019 Michael J. Prerau, Ph.D. - http://www.sleepEEG.org
%   This work is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License.
%   (http://creativecommons.org/licenses/by-nc-sa/4.0/)
%
%   Last modified 1/11/2019
%% ********************************************************************

% PROCESS DATA AND PARAMETERS
try
    %Process user input
    [data, Fs, frequency_range, time_bandwidth, num_tapers, winsize_samples, winstep_samples, ~, ~, min_NFFT, detrend_opt, plot_on, verbose] = process_input(varargin{:});
    
    
    if verbose
        display_spectrogram_props([time_bandwidth num_tapers], [winsize_samples winstep_samples], frequency_range, detrend_opt, Fs);
    end
    
    
    %Generate DPSS tapers (STEP 1)
    DPSS_tapers = dpss(winsize_samples, time_bandwidth, num_tapers) * sqrt(Fs);
    
    start_time = tic;
    %Compute the multitaper spectrogram
    [mt_spectrogram,stimes,sfreqs] = multitaper_spectrogram_coder_mex(single(data(:)'), Fs, frequency_range, DPSS_tapers, time_bandwidth, num_tapers, winsize_samples, winstep_samples, min_NFFT, detrend_opt);
    
    %% PLOT THE SPECTROGRAM
    
    %Show timing if verbose
    
    if verbose
        disp(' ');
        disp(['Estimation time: ' datestr(toc(start_time)*datenum([0 0 0 0 0 1]), 'HH:MM:SS.FFF')]);
    end
    
    %Plot the spectrogram
    if plot_on
        imagesc(stimes, sfreqs, nanpow2db(mt_spectrogram'));
        axis xy
        xlabel('Time (s)');
        ylabel('Frequency (Hz)');
        
        c = colorbar;
        ylabel(c,'Power (dB)');
        axis tight
    end
catch
    warning(['Mex file unavailable for system: ' computer ' . Reverting to matlab version']);
    [mt_spectrogram,stimes,sfreqs] = multitaper_spectrogram(varargin{:});
end
end


% ********************************************
%           HELPER FUNCTIONS
% ********************************************
%% PROCESS THE USER INPUT

function [data, Fs, frequency_range, time_bandwidth, num_tapers, winsize_samples, winstep_samples, window_start, num_windows, nfft, detrend_opt, plot_on, verbose] = process_input(varargin)
if length(varargin)<2
    error('Too few inputs. Need at least data and sampling rate');
end

%Set default values for inputs
default={[],[],[0 varargin{2}/2],[5 9], [5 1], 0, true, true, true};

%Allow the third input to be ploton
if nargin == 3 && islogical(varargin{3})
    default{6} = varargin{3};
    varargin = varargin(1:2);
end

%Handle defaults
inputs = default;
inputs(setdiff(1:length(varargin), find(cellfun(@isempty,varargin)))) = varargin(~cellfun(@isempty,(varargin)));

%Transfer input vector to parameters
[data, Fs, frequency_range, taper_params, data_window_params, min_NFFT, detrend_opt, plot_on, verbose] = deal(inputs{:});

%Set either linear or constant detrending
if detrend_opt ~= false
    switch lower(detrend_opt)
        case {'const','constant'}
            detrend_opt = 1;
        case {'none', 'off'}
            detrend_opt = 0;
        otherwise
            detrend_opt = 2;
    end
end

%Fix error in frequency range
if frequency_range(2) > Fs/2
    frequency_range(2) = Fs/2;
    warning(['Upper frequency range greater than Nyquist, setting range to [' num2str(frequency_range(1)) ' ' num2str(frequency_range(2)) ']']);
end


%Set the number of tapers if none supplied
time_bandwidth = taper_params(1);

%Set the number of tapers to 2 x floor(TW)-1 if none supplied
if length(taper_params) == 1
    num_tapers = floor(2*(time_bandwidth))-1;
    warning(['No taper number specified, setting number of tapers to ' num2str(num_tapers)]);
else
    num_tapers = taper_params(2);
end

%Throw warning for tapers
if num_tapers ~= floor(2*time_bandwidth(1) - 1)
    warning(['Number of tapers is optimal at floor(2*TW - 1). Consider using [' num2str(taper_params(1)) ' ' num2str(floor(2*taper_params(1) - 1)) ']']);
end

%Compute the data window and step size in samples
if mod(data_window_params(1)*Fs,1)
    winsize_samples=round(data_window_params(1)*Fs);
    warning(['Window size is not clearly divisible by sampling frequency. Adjusting window size to ' num2str(winsize_samples/Fs) ' seconds']);
else
    winsize_samples=data_window_params(1)*Fs;
end

if mod(data_window_params(2)*Fs,1)
    winstep_samples=round(data_window_params(2)*Fs);
    warning(['Window step size is not clearly divisible by sampling frequency. Adjusting window size to ' num2str(winstep_samples/Fs) ' seconds']);
else
    winstep_samples=data_window_params(2)*Fs;
end

%Total data length
N=length(data);

%Window start indices
window_start = 1:winstep_samples:N-winsize_samples+1;
%Number of windows
num_windows = length(window_start);

%Number of points in the FFT
nfft = max(max(2^(nextpow2(winsize_samples)),winsize_samples), 2^nextpow2(min_NFFT));
end

%% PROCESS THE SPECTROGRAM PARAMETERS

function [window_idxs, stimes, sfreqs, freq_inds] = process_spectrogram_params(Fs, nfft, frequency_range, window_start, datawin_size)
%Create the frequency vector
df = Fs/nfft;
sfreqs = df/2:df:(Fs-df/2); % all possible frequencies

%Set max frequency to nyquist if only lower bound specified
if length(frequency_range) == 1
    frequency_range(2) = Fs/2;
end

%Get just the frequencies for the given frequency range
freq_inds = (sfreqs >= frequency_range(1)) & (sfreqs <= frequency_range(2));
sfreqs = sfreqs(freq_inds);

%Compute the times of the middle of each spectrum
window_middle_times = window_start + round(datawin_size/2);
stimes = window_middle_times/Fs;

%Data windows
window_idxs = window_start' + (0:datawin_size-1);
end

%% DISPLAY SPECTROGRAM PROPERTIES

function display_spectrogram_props(taper_params, data_window_params, frequency_range, detrend_opt, Fs)
data_window_params = data_window_params/Fs;
%my_pool = gcp;
switch detrend_opt
    case 1
        det_string = 'Constant';
    case 2
        det_string = 'Linear';
    otherwise
        det_string='Off';
end

% Display spectrogram properties
disp(' ');
disp('Multitaper Spectrogram Properties:');
disp(' ');
disp(['    Spectral Resolution: ' num2str((2*taper_params(1))/data_window_params(1)) 'Hz']);
disp(['    Window Length: ' num2str(data_window_params(1)) 's']);
disp(['    Window Step: ' num2str(data_window_params(2)) 's']);
disp(['    Time Half-Bandwidth Product: ' num2str(taper_params(1))]);
disp(['    Number of Tapers: ' num2str(taper_params(2))]);
disp(['    Frequency Range: ' num2str(frequency_range(1)) 'Hz - ' num2str(frequency_range(2)) 'Hz']);
disp(['    Detrending: ' det_string]);
disp(' ');
%disp(['Estimating multitaper spectrogram on ' num2str(my_pool.NumWorkers) ' workers...']);
end

function ydB = nanpow2db(y)
%POW2DB   Power to dB conversion, setting all bad values to nan
%   YDB = POW2DB(Y) convert the data Y into its corresponding dB value YDB
%
%   % Example:
%   %   Calculate ratio of 2000W to 2W in decibels
%
%   y1 = pow2db(2000/2)     % Answer in db

%   Copyright 2006-2014 The MathWorks, Inc.
% EDITED BY MJP 2/7/2020

% #codegen
% cond = all(y(:)>=0);
% if ~cond
%     coder.internal.assert(cond,'signal:pow2db:InvalidInput');
% end

%ydB = 10*log10(y);
%ydB = db(y,'power');
% We want to guarantee that the result is an integer
% if y is a negative power of 10.  To do so, we force
% some rounding of precision by adding 300-300.

ydB = (10.*log10(y)+300)-300;
ydB(y(:)<=0) = nan;
end