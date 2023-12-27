#include <ESP32Servo.h>
#include "Arduino.h"
#include <ESPAsyncWebSrv.h>
#include <WiFi.h>
#include <AsyncTCP.h>
#include "html.h"//引入網頁分頁檔案

//宣告指令代碼
#define UP 1
#define DOWN 2
#define LEFT 3
#define RIGHT 4
#define UP_LEFT 5
#define UP_RIGHT 6
#define DOWN_LEFT 7
#define DOWN_RIGHT 8
#define SERVO1_FIRST 9
#define SERVO1_SECOND 10
#define SERVO2_FIRST 11
#define SERVO2_SECOND 12
#define STOP 0

#define FRONT_RIGHT_MOTOR 0
#define FRONT_LEFT_MOTOR 1


#define FORWARD 1
#define BACKWARD -1

struct MOTOR_PINS
{
  int pinIN1;
  int pinIN2;    
};

std::vector<MOTOR_PINS> motorPins = 
{
  {18, 19},  //設定馬達1腳位
  {22, 23},  //設定馬達2腳位
};
Servo servo1;//宣告Servo 名稱
Servo servo2;//宣告Servo 名稱
int serov1pin=25,serov2pin=26;//設定伺服馬達1與2的腳位
int s1_ang0=0,s2_ang0=0;//設定伺服馬達1與2的初始角度
int s1_ang=90,s2_ang=90;//設定伺服馬達1與2的開啟角度

const char* ssid     = "I Use Arch BTW";//設定wifi名稱(英文限定)
const char* password = "89648964";//設定wifi密碼(8字以上)

AsyncWebServer server(80);
AsyncWebSocket ws("/ws");
                                        


void rotateMotor(int motorNumber, int motorDirection)//設定馬達前進與後退
{
  if (motorDirection == FORWARD)
  {
    digitalWrite(motorPins[motorNumber].pinIN1, HIGH);
    digitalWrite(motorPins[motorNumber].pinIN2, LOW); 
       
  }
  else if (motorDirection == BACKWARD)
  {
    digitalWrite(motorPins[motorNumber].pinIN1, LOW);
    digitalWrite(motorPins[motorNumber].pinIN2, HIGH);
  }
  else
  {
    digitalWrite(motorPins[motorNumber].pinIN1, LOW);
    digitalWrite(motorPins[motorNumber].pinIN2, LOW);       
  }
}

void processCarMovement(String inputValue)
{
  Serial.printf("Got value as %s %d\n", inputValue.c_str(), inputValue.toInt());  
  switch(inputValue.toInt())//設定網頁控制馬達指令
  {

    case UP:
      rotateMotor(FRONT_RIGHT_MOTOR, FORWARD);
      rotateMotor(FRONT_LEFT_MOTOR, FORWARD);             
      break;
  
    case DOWN:
      rotateMotor(FRONT_RIGHT_MOTOR, BACKWARD);
      rotateMotor(FRONT_LEFT_MOTOR, BACKWARD);  
      break;
  
    case LEFT:
      rotateMotor(FRONT_RIGHT_MOTOR, FORWARD);
      rotateMotor(FRONT_LEFT_MOTOR, BACKWARD); 
      break;
  
    case RIGHT:
      rotateMotor(FRONT_RIGHT_MOTOR, BACKWARD);
      rotateMotor(FRONT_LEFT_MOTOR, FORWARD); 
      break;
  
    case UP_LEFT:
      rotateMotor(FRONT_RIGHT_MOTOR, FORWARD);
      rotateMotor(FRONT_LEFT_MOTOR, STOP); 
      break;
  
    case UP_RIGHT:
      rotateMotor(FRONT_RIGHT_MOTOR, STOP);
      rotateMotor(FRONT_LEFT_MOTOR, FORWARD); 
      break;
  
    case DOWN_LEFT:
      rotateMotor(FRONT_RIGHT_MOTOR, STOP);
      rotateMotor(FRONT_LEFT_MOTOR, BACKWARD);
      break;
  
    case DOWN_RIGHT:
      rotateMotor(FRONT_RIGHT_MOTOR, BACKWARD);
      rotateMotor(FRONT_LEFT_MOTOR, STOP);   
      break;
  
    case SERVO1_FIRST:
       servo1.write(s1_ang0);//指定SERVO1轉到初始角度
      
      break;
  
    case SERVO1_SECOND:
      servo1.write(s1_ang);//指定SERVO1轉到設定角度
      break;

    case SERVO2_FIRST:
       servo2.write(s2_ang0);//指定SERVO2轉到初始角度
      
      break;
  
    case SERVO2_SECOND:
      servo2.write(s2_ang); //指定SERVO2轉到設定角度
      break;
  
    case STOP:
      rotateMotor(FRONT_RIGHT_MOTOR, STOP);
      rotateMotor(FRONT_LEFT_MOTOR, STOP);
          
      break;
  
    default:
      rotateMotor(FRONT_RIGHT_MOTOR, STOP);
      rotateMotor(FRONT_LEFT_MOTOR, STOP);    
      break;
  }
}

void handleRoot(AsyncWebServerRequest *request) 
{
  request->send_P(200, "text/html", htmlHomePage);
}

void handleNotFound(AsyncWebServerRequest *request) 
{
    request->send(404, "text/plain", "File Not Found");
}


void onWebSocketEvent(AsyncWebSocket *server, 
                      AsyncWebSocketClient *client, 
                      AwsEventType type,
                      void *arg, 
                      uint8_t *data, 
                      size_t len) 
{                      
  switch (type) 
  {
    case WS_EVT_CONNECT:
      Serial.printf("WebSocket client #%u connected from %s\n", client->id(), client->remoteIP().toString().c_str());
      //client->text(getRelayPinsStatusJson(ALL_RELAY_PINS_INDEX));
      break;
    case WS_EVT_DISCONNECT:
      Serial.printf("WebSocket client #%u disconnected\n", client->id());
      processCarMovement("0");
      break;
    case WS_EVT_DATA:
      AwsFrameInfo *info;
      info = (AwsFrameInfo*)arg;
      if (info->final && info->index == 0 && info->len == len && info->opcode == WS_TEXT) 
      {
        std::string myData = "";
        myData.assign((char *)data, len);
        processCarMovement(myData.c_str());       
      }
      break;
    case WS_EVT_PONG:
    case WS_EVT_ERROR:
      break;
    default:
      break;  
  }
}

void setUpPinModes()
{
  for (int i = 0; i < motorPins.size(); i++)
  {
    pinMode(motorPins[i].pinIN1,OUTPUT);//設定馬達腳位INPUT?OUTPUT?
    pinMode(motorPins[i].pinIN2,OUTPUT);//設定馬達腳位INPUT?OUTPUT?
    rotateMotor(i, STOP);  
  }
}


void setup(void) 
{
  servo1.attach(serov1pin);
  servo2.attach(serov2pin);
  servo1.write(s1_ang0);
  servo2.write(s2_ang0);
  setUpPinModes();
  Serial.begin(115200);
  int channel=6;//設定wifi頻道1~11
  WiFi.softAP(ssid, password, channel);
  IPAddress IP = WiFi.softAPIP();
  Serial.print("AP IP address: ");
  Serial.println(IP);
  server.on("/", HTTP_GET, handleRoot);
  server.onNotFound(handleNotFound);
  
  ws.onEvent(onWebSocketEvent);
  server.addHandler(&ws);
  
  server.begin();
  Serial.println("HTTP server started");
}

void loop() 
{
  ws.cleanupClients(); 
}
