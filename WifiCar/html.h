const char* htmlHomePage PROGMEM = R"HTMLHOMEPAGE(
<!DOCTYPE html>
<html>
  <head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <style>
    .arrows {
      font-size:70px;
      color:red;
    }
    .circularArrows {
      font-size:80px;
      color:blue;
    }
    td {
      background-color:black;
      border-radius:25%;
      box-shadow: 5px 5px #888888;
    }
    td:active {
      transform: translate(5px,5px);
      box-shadow: none; 
    }
    .noselect {
      -webkit-touch-callout: none; /* iOS Safari */
        -webkit-user-select: none; /* Safari */
         -khtml-user-select: none; /* Konqueror HTML */
           -moz-user-select: none; /* Firefox */
            -ms-user-select: none; /* Internet Explorer/Edge */
                user-select: none; /* Non-prefixed version, currently
                                      supported by Chrome and Opera */
    }
    </style>
  </head>
  <body class="noselect" align="center" style="background-color:white">
     
    <h1 style="color: teal;text-align:center;">Mobile Controller</h1> <!--設定標題-->
    <h2 style="color: teal;text-align:center;">Make Sure You're On Mobile!</h2> <!--副標題-->
    
    <table id="mainTable" style="width:400px;margin:auto;table-layout:fixed" CELLSPACING=10>
      <tr>
        <td ontouchstart='onTouchStartAndEnd("5")' ontouchend='onTouchStartAndEnd("0")'><span class="arrows" >&#11017;</span></td>
        <td ontouchstart='onTouchStartAndEnd("1")' ontouchend='onTouchStartAndEnd("0")'><span class="arrows" >&#8679;</span></td>
        <td ontouchstart='onTouchStartAndEnd("6")' ontouchend='onTouchStartAndEnd("0")'><span class="arrows" >&#11016;</span></td>
      </tr>
      
      <tr>
        <td ontouchstart='onTouchStartAndEnd("3")' ontouchend='onTouchStartAndEnd("0")'><span class="arrows" >&#8678;</span></td>
        <td></td>    
        <td ontouchstart='onTouchStartAndEnd("4")' ontouchend='onTouchStartAndEnd("0")'><span class="arrows" >&#8680;</span></td>
      </tr>
      <tr>
        <td ontouchstart='onTouchStartAndEnd("7")' ontouchend='onTouchStartAndEnd("0")'><span class="arrows" >&#11019;</span></td>
        <td ontouchstart='onTouchStartAndEnd("2")' ontouchend='onTouchStartAndEnd("0")'><span class="arrows" >&#8681;</span></td>
        <td ontouchstart='onTouchStartAndEnd("8")' ontouchend='onTouchStartAndEnd("0")'><span class="arrows" >&#11018;</span></td>
      </tr>
       </table>
      <table id="mainTable" style="width:400px;margin:auto;table-layout:fixed" CELLSPACING=10>
      <tr>
       <th>servo1角度控制</th>
      </tr>
        <td ontouchstart='onTouchStartAndEnd("9")' ontouchend='onTouchStartAndEnd("0")'><span class="circularArrows" >&#8634;</span></td><!--servo1回到初始角度-->
        <td style="background-color:white;box-shadow:none"></td>    
        <td ontouchstart='onTouchStartAndEnd("10")' ontouchend='onTouchStartAndEnd("0")'><span class="circularArrows" >&#8635;</span></td><!--servo1轉到指定角度-->
      </tr>
      <tr>
        <th>servo2角度控制</th>
      </tr>
        <td ontouchstart='onTouchStartAndEnd("11")' ontouchend='onTouchStartAndEnd("0")'><span class="circularArrows" >&#8634;</span></td><!--servo2回到初始角度-->
        <td style="background-color:white;box-shadow:none"></td>    
        <td ontouchstart='onTouchStartAndEnd("12")' ontouchend='onTouchStartAndEnd("0")'><span class="circularArrows" >&#8635;</span></td><!--servo2,轉到指定角度-->
      </tr>
    </table>
    <script>
      var webSocketUrl = "ws:\/\/" + window.location.hostname + "/ws";
      var websocket;
      
      function initWebSocket() 
      {
        websocket = new WebSocket(webSocketUrl);
        websocket.onopen    = function(event){};
        websocket.onclose   = function(event){setTimeout(initWebSocket, 2000);};
        websocket.onmessage = function(event){};
      }
      function onTouchStartAndEnd(value) 
      {
        websocket.send(value);
      }
          
      window.onload = initWebSocket;
      document.getElementById("mainTable").addEventListener("touchend", function(event){
        event.preventDefault()
      });      
    </script> <!--設定圖片-->
    <img src=" data:image/png;base64,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" >
  </body>
</html> 
)HTMLHOMEPAGE";                           
