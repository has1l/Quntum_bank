const io = require('socket.io')(3001, {
  cors: { origin: '*' }
});

console.log('Signaling server started on port 3001');

// Очередь звонков: [{ userId, name, time, socketId, createdAt }]
let callQueue = [];
let operators = new Set();

function updateQueue() {
  const now = Date.now();
  io.to('operators').emit('queue_update', callQueue.map(item => ({
    userId: item.userId,
    name: item.name,
    waitingTime: Math.floor((now - item.createdAt) / 1000)
  })));
}

io.on('connection', socket => {
  // Клиент отправляет запрос на звонок
  socket.on('call_request', ({ userId, name }) => {
    if (!callQueue.find(item => item.userId === userId)) {
      callQueue.push({ userId, name, socketId: socket.id, createdAt: Date.now() });
      updateQueue();
      console.log('CALL_REQUEST:', userId, name);
    }
    socket.join(userId); // чтобы потом отправить call_accepted
  });

  // Оператор подключается
  socket.on('operator_join', () => {
    socket.join('operators');
    operators.add(socket.id);
    updateQueue();
    console.log('OPERATOR_JOIN:', socket.id);
  });

  // Оператор принимает звонок
  socket.on('accept_call', ({ userId }) => {
    const idx = callQueue.findIndex(item => item.userId === userId);
    if (idx !== -1) {
      const call = callQueue[idx];
      callQueue.splice(idx, 1);
      updateQueue();
      io.to(call.userId).emit('call_accepted', { operatorId: 'operator' });
      console.log('CALL_ACCEPTED:', userId);
    }
  });

  // Обычный signaling для WebRTC
  socket.on('signal', data => {
    console.log('SIGNAL:', data);
    io.to(data.to).emit('signal', data);
  });

  socket.on('join', id => {
    console.log('JOIN:', id);
    socket.join(id);
  });

  socket.on('disconnect', () => {
    operators.delete(socket.id);
    // Удаляем из очереди все звонки, чей сокет отключился
    callQueue = callQueue.filter(item => item.socketId !== socket.id);
    updateQueue();
  });
}); 