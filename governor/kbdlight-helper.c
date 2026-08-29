/* kbdlight-helper (Power House shim) — NOT setuid. Same interface as the old
 * helper (pwm daemon on stdin duty lines / on / off / read) but every request
 * goes to the governor's socket; nothing here touches hardware. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <signal.h>
static int conn(void){
  int s=socket(AF_UNIX,SOCK_STREAM,0); struct sockaddr_un a={0}; a.sun_family=AF_UNIX;
  const char*p=getenv("POWERHOUSE_SOCK"); strncpy(a.sun_path,p?p:"/run/powerhouse/sock",sizeof a.sun_path-1);
  if(connect(s,(struct sockaddr*)&a,sizeof a)){perror("powerhouse socket");exit(1);} return s;
}
static void send_line(int s,const char*l){ write(s,l,strlen(l)); char b[512]; read(s,b,sizeof b); }
int main(int argc,char**argv){
  signal(SIGPIPE,SIG_IGN);
  int s=conn();
  if(argc>=2 && strcmp(argv[1],"pwm")!=0){
    if(!strcmp(argv[1],"on")) send_line(s,"{\"op\":\"kbd\",\"cmd\":\"on\"}\n");
    else if(!strcmp(argv[1],"off")) send_line(s,"{\"op\":\"kbd\",\"cmd\":\"off\"}\n");
    write(s,"{\"op\":\"kbd\",\"cmd\":\"read\"}\n",27); char b[256]={0}; int n=read(s,b,255);
    char*v=n>0?strstr(b,"\"value\": "):0; if(!v) v=n>0?strstr(b,"\"value\":"):0;
    if(v){ printf("%02x\n", atoi(v+ (v[8]==' '?9:8))); } else printf("--\n");
    return 0;
  }
  char buf[256]; int last=-1;
  while(fgets(buf,sizeof buf,stdin)){
    int d=atoi(buf); if(d<0)d=0; if(d>100)d=100;
    if(d!=last){ char m[64]; snprintf(m,sizeof m,"{\"op\":\"kbd\",\"duty\":%d}\n",d); send_line(s,m); last=d; }
  }
  send_line(s,"{\"op\":\"kbd\",\"cmd\":\"on\"}\n");   /* EOF: leave the keys on, like the old helper */
  return 0;
}
