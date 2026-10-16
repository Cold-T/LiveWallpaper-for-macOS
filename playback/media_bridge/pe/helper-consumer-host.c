/* Controlled original winrtutil64 consumer fixture host. Never calls AppleEvents.
 * Creates only per-process pipes; launches only the operator-provided helper.
 * Optional --initialize-readonly sends only the original empty blocklist config.
 * stdout: exact 1024-byte original protocol frames; stderr: status + DLL traces.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <wchar.h>
#include <fcntl.h>
#include <io.h>
static void status(const char *name,DWORD code){fprintf(stderr,"[LWHelperHost] %s code=%lu\n",name,(unsigned long)code);fflush(stderr);}
static BOOL connect_pipe(HANDLE pipe){
    if(ConnectNamedPipe(pipe,NULL))return TRUE;
    DWORD error=GetLastError();return error==ERROR_PIPE_CONNECTED;
}
int wmain(int argc,wchar_t **argv){
    if(argc!=3&&argc!=4){fputs("usage: helper-consumer-host.exe <absolute-winrtutil64.exe> <seconds1..120> [--initialize-readonly]\n",stderr);return 2;}
    BOOL initialize=argc==4&&!wcscmp(argv[3],L"--initialize-readonly");
    if(argc==4&&!initialize)return 2;
    wchar_t *end=NULL;long seconds=wcstol(argv[2],&end,10);
    if(*end||seconds<1||seconds>120||wcslen(argv[1])>30000||wcschr(argv[1],L'"'))return 2;
    _setmode(_fileno(stdout),_O_BINARY);
    DWORD pid=GetCurrentProcessId();wchar_t base[128],input_name[160],output_name[160];
    swprintf(base,128,L"LiveWallpaperFixture-%lu-%llu",(unsigned long)pid,(unsigned long long)GetTickCount64());
    swprintf(input_name,160,L"\\\\.\\pipe\\%ls",base);
    swprintf(output_name,160,L"\\\\.\\pipe\\%lsClient",base);
    HANDLE input=CreateNamedPipeW(input_name,PIPE_ACCESS_OUTBOUND|FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_NOWAIT|PIPE_REJECT_REMOTE_CLIENTS,1,16384,16384,0,NULL);
    if(input==INVALID_HANDLE_VALUE){status("create_input_failed",GetLastError());return 3;}
    HANDLE output=CreateNamedPipeW(output_name,PIPE_ACCESS_INBOUND|FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_NOWAIT|PIPE_REJECT_REMOTE_CLIENTS,1,16384,16384,0,NULL);
    if(output==INVALID_HANDLE_VALUE){status("create_output_failed",GetLastError());CloseHandle(input);return 3;}
    wchar_t command[32768];swprintf(command,32768,L"\"%ls\" -mediainterface -messagehandler %ls -parentprocess %lu",argv[1],base,(unsigned long)pid);
    STARTUPINFOW startup={0};startup.cb=sizeof(startup);PROCESS_INFORMATION process={0};
    if(!CreateProcessW(argv[1],command,NULL,NULL,TRUE,CREATE_NO_WINDOW,NULL,NULL,&startup,&process)){
      status("launch_failed",GetLastError());CloseHandle(input);CloseHandle(output);return 4;
    }
    CloseHandle(process.hThread);status("child_started",process.dwProcessId);
    BOOL input_connected=FALSE,output_connected=FALSE,initialized=FALSE;DWORD frames=0;int result=0;
    ULONGLONG deadline=GetTickCount64()+(ULONGLONG)seconds*1000;
    while(GetTickCount64()<deadline){
      if(!input_connected)input_connected=connect_pipe(input);
      if(!output_connected)output_connected=connect_pipe(output);
      if(initialize&&input_connected&&output_connected&&!initialized){
        /* Original engine sends type6 immediately after helper launch.
         * Empty JSON blocklist -> refresh current selection; no playback control.
         * Frame format recovered from original callback and engine sender. */
        DWORD packet[256]={0};packet[0]=6;packet[1]=0;packet[2]=2;
        ((BYTE *)packet)[12]='[';((BYTE *)packet)[13]=']';DWORD written=0;
        if(!WriteFile(input,packet,sizeof(packet),&written,NULL)||written!=sizeof(packet)){
          status("readonly_initialization_failed",GetLastError());result=9;break;
        }
        initialized=TRUE;status("readonly_empty_blocklist_sent_once",6);
      }
      if(output_connected){
        BYTE frame[1024];DWORD count=0;
        if(ReadFile(output,frame,sizeof(frame),&count,NULL)){
          if(count){
            if(count!=1024){status("unexpected_frame_size",count);result=5;break;}
            if(fwrite(frame,1,count,stdout)!=count){result=6;break;}
            fflush(stdout);frames++;
          }
        }else{
          DWORD error=GetLastError();
          if(error!=ERROR_NO_DATA&&error!=ERROR_PIPE_LISTENING){status("read_failed",error);result=7;break;}
        }
      }
      if(WaitForSingleObject(process.hProcess,0)==WAIT_OBJECT_0){
        DWORD code;GetExitCodeProcess(process.hProcess,&code);status("child_exited",code);if(code)result=8;break;
      }
      Sleep(10);
    }
    status("frames_captured",frames);
    /* Stop only the child we just created. Broken pipes give it a chance to exit. */
    CloseHandle(input);CloseHandle(output);
    if(WaitForSingleObject(process.hProcess,2000)==WAIT_TIMEOUT){
      status("owned_child_timeout_terminate",0);TerminateProcess(process.hProcess,0x102);
      WaitForSingleObject(process.hProcess,3000);
    }
    CloseHandle(process.hProcess);return result;
}
