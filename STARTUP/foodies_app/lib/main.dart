import 'package:flutter/material.dart';
void main(){
  runApp(
    MaterialApp(
      title: 'Foodies App',
      home: Scaffold(
        appBar: AppBar(
          title: Text(
            'Foodiez'.toUpperCase(),
              style: TextStyle(fontFamily: "Oswald" , fontSize: 35.0, color: Colors.tealAccent),
        ),
          backgroundColor: Colors.purpleAccent,
        ),
        body: Center(
          child: Text(
              "Hello World",
              textDirection: TextDirection.ltr, )
        ),
      )
    )
  );
}