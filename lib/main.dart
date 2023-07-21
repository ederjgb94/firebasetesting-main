import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:faker/faker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebasetesting/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:connectivity/connectivity.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await GetStorage.init();

  var db = FirebaseFirestore.instance;
  await db.waitForPendingWrites();
  db.settings = const Settings(
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // FirebaseFirestore.instance.useFirestoreEmulator('10.0.2.2', 8080);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final int _counter = 0;
  var db = FirebaseFirestore.instance;
  var rl = FirebaseDatabase.instance.ref();

  Future<bool> isConnected() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> _incrementCounter() async {
    var db = FirebaseFirestore.instance;
    var time = FieldValue.serverTimestamp();

    await db.collection('users').add(
      {
        'first': faker.person.firstName(),
        'last': faker.person.lastName(),
        'timestamp': time,
      },
    );
    await rlUpdate();
    // setState(() {});
  }

  Future obtener() async {
    Source CACHE = Source.cache;
    Source SERVER = Source.server;

    FirebaseFirestore db = FirebaseFirestore.instance;
    var userCache = await db
        .collection("users")
        .orderBy("timestamp", descending: true)
        .limit(1)
        .get(
          GetOptions(source: CACHE),
        );
    return userCache.docs;
  }

  Future testobtener() async {
    Source CACHE = Source.cache;
    Source SERVER = Source.server;

    FirebaseFirestore db = FirebaseFirestore.instance;

    var box = GetStorage();

    var cacheTime = box.read('cacheTime');

    if (cacheTime == null) {
      var profesoresServer = await db
          .collection("ciclos")
          .doc('2023 - 3 Otoño')
          .collection('profesores')
          .orderBy('lastUpdate', descending: true)
          .get(
            GetOptions(source: SERVER),
          );
      await box.write('cacheTime',
          profesoresServer.docs.first.data()['lastUpdate'].toDate().toString());
      print(box.read('cacheTime').toString());
      return profesoresServer.docs;
    } else {
      var cacheTime = box.read('cacheTime');
      print(cacheTime.toString());

      //actualiza mi cache
      //si no hay internet no se actualiza
      if (await isConnected()) {
        var profesoresLinea = await db
            .collection('ciclos')
            .doc('2023 - 3 Otoño')
            .collection('profesores')
            .where(
              'lastUpdate',
              isGreaterThan: Timestamp.fromDate(DateTime.parse(cacheTime)),
            )
            .get(
              GetOptions(source: SERVER),
            );
        if (kDebugMode) {
          print('se trajeron de linea: ${profesoresLinea.docs.length}');
        }
        if (profesoresLinea.docs.isNotEmpty) {
          await box.write(
              'cacheTime',
              profesoresLinea.docs.first
                  .data()['lastUpdate']
                  .toDate()
                  .toString());
        }
      }

      //obtengo mi cache con datos actualizados
      var profesores = await db
          .collection('ciclos')
          .doc('2023 - 3 Otoño')
          .collection('profesores')
          .orderBy('lastUpdate', descending: true)
          .get(
            GetOptions(source: CACHE),
          );
      if (kDebugMode) {
        print('se trajeron del cache: ${profesores.docs.length}');
      }
      //actualizo cache

      return profesores.docs;
    }
  }

  Future<void> rlUpdate() async {
    if (await isConnected()) {
      await rl.set(
        {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      );
    }
  }

  Widget listaUsers() {
    return FutureBuilder(
      future: testobtener(),
      builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
        if (snapshot.hasData) {
          return ListView.builder(
            itemCount: snapshot.data.length,
            itemBuilder: (BuildContext context, int index) {
              return ListTile(
                onTap: () async {
                  var profesor = snapshot.data[index];
                  await db
                      .collection('ciclos')
                      .doc('2023 - 3 Otoño')
                      .collection('profesores')
                      .doc(profesor.id)
                      .update(
                    {
                      'nombre': 'updated ${faker.person.firstName()}',
                      'lastUpdate': FieldValue.serverTimestamp(),
                    },
                  );
                  await rlUpdate();

                  //prueba de eliminar...
                  // var user = snapshot.data[index];
                  // await db.collection('users').doc(user.id).delete();
                  // setState(() {});
                },
                title: Text('$index ${snapshot.data[index].data()['nombre']}'),
                subtitle: Text(snapshot.data[index]
                    .data()['lastUpdate']
                    .toDate()
                    .toString()),
              );
            },
          );
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: FutureBuilder(
        future: isConnected(),
        builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
          if (snapshot.hasData && snapshot.data == true) {
            return StreamBuilder<DatabaseEvent>(
              stream: () {
                var ref = FirebaseDatabase.instance.ref();
                return ref.onChildChanged;
              }(),
              builder: (BuildContext context,
                  AsyncSnapshot<DatabaseEvent> snapshot) {
                if (snapshot.hasError) {
                  return const Text('Error al obtener los datos');
                }

                // if (snapshot.connectionState == ConnectionState.waiting) {
                //   return listaUsers();
                // }

                // if (snapshot.hasData) {
                //   final data = snapshot.data!.snapshot.value;
                //   // Procesa los datos como desees
                //   return listaUsers();
                // }

                return listaUsers();
              },
            );
          } else {
            return listaUsers();
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        // onPressed: () {
        //   db
        //       .collection('ciclos')
        //       .doc('2023 - 3 Otoño')
        //       .collection('profesores')
        //       .doc('12228-TOLEDO BARAJAS LEONOR ')
        //       .collection('abc')
        //       .get(
        //         const GetOptions(source: Source.server),
        //       )
        //       .then((value) => print(value.docs.length));
        // },
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
