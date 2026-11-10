#include <errno.h>
#include <poll.h>
#include <stdlib.h>

static Term unix_socket_poll_many_fail(Env e, Term interests,
  struct pollfd* descriptors, uint32_t* connection_ids, int code) {
  free(descriptors);
  free(connection_ids);
  return io_tup(e, interests, io_fail(e, code, NULL));
}

Term unix_socket_poll_many_run(Env e, Term* f, IoWork* w) {
  Term interests = f[0];
  uint64_t timeout = (uint64_t)f[1];
  uint32_t count = 0;
  Term cursor = interests;
  while (term_tag(cursor) == TAG_CTR && term_aux(cursor) == CID_Con) {
    if (count == UINT32_MAX) {
      return unix_socket_poll_many_fail(e, interests, NULL, NULL, EOVERFLOW);
    }
    uint64_t location = term_peek(e.mem, cursor);
    cursor = e.mem[location + 1];
    count += 1;
  }
  if (term_tag(cursor) != TAG_PAK || term_aux(cursor) != CID_Nil) {
    return unix_socket_poll_many_fail(e, interests, NULL, NULL, EINVAL);
  }
  if ((size_t)count > SIZE_MAX / sizeof(struct pollfd) ||
      (size_t)count > SIZE_MAX / sizeof(uint32_t)) {
    return unix_socket_poll_many_fail(e, interests, NULL, NULL, EOVERFLOW);
  }
  struct pollfd* descriptors = count == 0 ? NULL
    : malloc((size_t)count * sizeof(struct pollfd));
  if (count != 0 && descriptors == NULL) {
    return unix_socket_poll_many_fail(e, interests, NULL, NULL, ENOMEM);
  }
  uint32_t* connection_ids = count == 0 ? NULL
    : malloc((size_t)count * sizeof(uint32_t));
  if (count != 0 && connection_ids == NULL) {
    return unix_socket_poll_many_fail(e, interests, descriptors, NULL, ENOMEM);
  }
  cursor = interests;
  for (uint32_t index = 0; index < count; index += 1) {
    uint64_t list_location = term_peek(e.mem, cursor);
    Term interest = e.mem[list_location];
    if (term_tag(interest) != TAG_CTR || cid_arity(term_aux(interest)) != 3) {
      return unix_socket_poll_many_fail(e, interests, descriptors,
        connection_ids, EINVAL);
    }
    uint64_t interest_location = term_peek(e.mem, interest);
    Term socket = e.mem[interest_location + 1];
    if (term_tag(socket) != TAG_PAK) {
      return unix_socket_poll_many_fail(e, interests, descriptors,
        connection_ids, EINVAL);
    }
    connection_ids[index] = (uint32_t)e.mem[interest_location];
    descriptors[index] = (struct pollfd){
      .fd = (int)io_hand_v(socket),
      .events = (short)(uint32_t)e.mem[interest_location + 2],
      .revents = 0
    };
    cursor = e.mem[list_location + 1];
  }
  int wait_ms = timeout > 2147483647u ? 2147483647 : (int)timeout;
  int ready = poll(descriptors, (nfds_t)count, wait_ms);
  int error = ready < 0 ? errno : 0;
  if (error != 0) {
    free(descriptors);
    free(connection_ids);
    (void)w;
    return io_tup(e, interests, io_fail(e, error, NULL));
  }
  Term events = term_pak(CID_Nil, 0);
  for (uint32_t index = count; index > 0; index -= 1) {
    if (descriptors[index - 1].revents == 0) {
      continue;
    }
    Term event = io_node(e,
      CID_______src_coordinator_UnixSocketTypes_ReadyEvent,
      (Term)connection_ids[index - 1],
      (Term)(uint16_t)descriptors[index - 1].revents);
    if (err_seen(e.mem)) {
      term_drop(e, events);
      free(descriptors);
      free(connection_ids);
      (void)w;
      return io_tup(e, interests, io_fail(e, ENOMEM, NULL));
    }
    Term next_events = io_node(e, CID_Con, event, events);
    if (err_seen(e.mem)) {
      term_drop(e, event);
      term_drop(e, events);
      free(descriptors);
      free(connection_ids);
      (void)w;
      return io_tup(e, interests, io_fail(e, ENOMEM, NULL));
    }
    events = next_events;
  }
  free(descriptors);
  free(connection_ids);
  (void)w;
  return io_tup(e, interests, io_done(e, events));
}

static void __attribute__((constructor)) unix_socket_poll_many_use(void) {
  io_eff(CID(unix_socket_poll_many), unix_socket_poll_many_run);
}
